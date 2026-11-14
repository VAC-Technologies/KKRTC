from asgiref.sync import async_to_sync, sync_to_async
from channels.testing import WebsocketCommunicator
from django.contrib.auth import get_user_model
from django.test import TestCase, TransactionTestCase
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.buses.models import Bus
from apps.routes.models import Route
from apps.trips.models import Trip
from config.asgi import application


class StartTripApiTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.pilot = user_model.objects.create_user(username='pilot')
        UserProfile.objects.create(user=self.pilot, role=UserProfile.Role.PILOT)
        self.passenger = user_model.objects.create_user(username='passenger')
        UserProfile.objects.create(
            user=self.passenger, role=UserProfile.Role.PASSENGER
        )
        self.bus = Bus.objects.create(
            registration_number='KA-34-A-1001', pilot=self.pilot
        )
        self.route = Route.objects.create(
            source_name='Ballari', destination_name='Kampli'
        )
        self.client = APIClient()

    def test_authenticated_pilot_starts_trip_and_gets_contract(self):
        self.client.force_authenticate(self.pilot)

        response = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': self.bus.id},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        trip = Trip.objects.get(pk=response.data['trip_id'])
        self.assertEqual(trip.status, Trip.Status.ACTIVE)
        self.assertEqual(trip.pilot, self.pilot)
        self.assertEqual(trip.bus, self.bus)
        self.assertEqual(trip.route, self.route)
        self.assertIsNotNone(trip.start_time)
        self.assertEqual(response.data['route'], 'Ballari - Kampli')
        self.assertEqual(response.data['status'], 'ACTIVE')
        self.assertIn('start_time', response.data)

    def test_passenger_cannot_start_trip(self):
        self.client.force_authenticate(self.passenger)
        response = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': self.bus.id},
            format='json',
        )
        self.assertEqual(response.status_code, 403)
        self.assertFalse(Trip.objects.exists())

    def test_anonymous_user_cannot_start_trip(self):
        response = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': self.bus.id},
            format='json',
        )
        self.assertEqual(response.status_code, 401)

    def test_pilot_cannot_start_another_active_trip(self):
        Trip.objects.create(pilot=self.pilot, bus=self.bus, route=self.route)
        self.client.force_authenticate(self.pilot)
        response = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': self.bus.id},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(Trip.objects.filter(pilot=self.pilot).count(), 1)

    def test_pilot_cannot_start_trip_using_another_pilots_bus(self):
        other_pilot = get_user_model().objects.create_user(username='other-pilot')
        UserProfile.objects.create(user=other_pilot, role=UserProfile.Role.PILOT)
        other_bus = Bus.objects.create(
            registration_number='KA-34-A-2002', pilot=other_pilot
        )
        self.client.force_authenticate(self.pilot)
        response = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': other_bus.id},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertFalse(Trip.objects.exists())

    def test_active_trips_endpoint_returns_empty_when_no_trip_exists(self):
        self.client.force_authenticate(self.passenger)
        response = self.client.get('/api/trips/active/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [])

    def test_starting_pilot_can_end_trip_and_history_is_retained(self):
        trip = Trip.objects.create(pilot=self.pilot, bus=self.bus, route=self.route)
        self.client.force_authenticate(self.pilot)

        response = self.client.post(
            '/api/trips/end/', {'trip_id': trip.id}, format='json'
        )

        self.assertEqual(response.status_code, 200)
        trip.refresh_from_db()
        self.assertEqual(trip.status, Trip.Status.COMPLETED)
        self.assertIsNotNone(trip.end_time)
        self.assertEqual(response.data['status'], 'COMPLETED')
        self.assertIn('end_time', response.data)
        self.assertTrue(Trip.objects.filter(pk=trip.pk).exists())
        self.assertFalse(
            Trip.objects.filter(status=Trip.Status.ACTIVE).exists()
        )

    def test_different_pilot_cannot_end_trip(self):
        trip = Trip.objects.create(pilot=self.pilot, bus=self.bus, route=self.route)
        other_pilot = get_user_model().objects.create_user(username='other-pilot')
        UserProfile.objects.create(user=other_pilot, role=UserProfile.Role.PILOT)
        self.client.force_authenticate(other_pilot)

        response = self.client.post(
            '/api/trips/end/', {'trip_id': trip.id}, format='json'
        )

        self.assertEqual(response.status_code, 403)
        trip.refresh_from_db()
        self.assertEqual(trip.status, Trip.Status.ACTIVE)
        self.assertIsNone(trip.end_time)

    def test_passenger_cannot_end_trip(self):
        trip = Trip.objects.create(pilot=self.pilot, bus=self.bus, route=self.route)
        self.client.force_authenticate(self.passenger)

        response = self.client.post(
            '/api/trips/end/', {'trip_id': trip.id}, format='json'
        )

        self.assertEqual(response.status_code, 403)
        trip.refresh_from_db()
        self.assertEqual(trip.status, Trip.Status.ACTIVE)

    def test_anonymous_user_cannot_end_trip(self):
        trip = Trip.objects.create(pilot=self.pilot, bus=self.bus, route=self.route)

        response = self.client.post(
            '/api/trips/end/', {'trip_id': trip.id}, format='json'
        )

        self.assertEqual(response.status_code, 401)


class ActiveTripsWebsocketTests(TransactionTestCase):
    def setUp(self):
        user_model = get_user_model()
        self.pilot = user_model.objects.create_user(username='ws-pilot')
        UserProfile.objects.create(user=self.pilot, role=UserProfile.Role.PILOT)
        self.bus = Bus.objects.create(
            registration_number='KA-34-A-3003', pilot=self.pilot
        )
        self.route = Route.objects.create(
            source_name='Ballari', destination_name='Kampli'
        )
        self.client = APIClient()
        self.client.force_authenticate(self.pilot)

    def test_trip_start_and_end_events_are_broadcast_to_passengers(self):
        async def exercise_websocket():
            communicator = WebsocketCommunicator(
                application,
                '/ws/active-trips/',
                headers=[
                    (b'host', b'localhost'),
                    (b'origin', b'http://localhost'),
                ],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            snapshot = await communicator.receive_json_from()
            self.assertEqual(snapshot, {'event': 'active_trips', 'trips': []})

            response = await sync_to_async(
                self.client.post, thread_sensitive=True
            )(
                '/api/trips/start/',
                {'route_id': self.route.id, 'bus_id': self.bus.id},
                format='json',
            )
            self.assertEqual(response.status_code, 201)
            event = await communicator.receive_json_from()
            self.assertEqual(
                event,
                {
                    'event': 'trip_started',
                    'trip_id': response.data['trip_id'],
                    'route': 'Ballari - Kampli',
                    'status': 'ACTIVE',
                },
            )

            end_response = await sync_to_async(
                self.client.post, thread_sensitive=True
            )(
                '/api/trips/end/',
                {'trip_id': response.data['trip_id']},
                format='json',
            )
            self.assertEqual(end_response.status_code, 200)
            ended_event = await communicator.receive_json_from()
            self.assertEqual(
                ended_event,
                {
                    'event': 'trip_ended',
                    'trip_id': response.data['trip_id'],
                    'status': 'COMPLETED',
                },
            )
            await communicator.disconnect()

        async_to_sync(exercise_websocket)()


class TripLocationTrackingTests(TransactionTestCase):
    def setUp(self):
        user_model = get_user_model()
        self.pilot = user_model.objects.create_user(username='loc-pilot')
        UserProfile.objects.create(user=self.pilot, role=UserProfile.Role.PILOT)
        self.passenger = user_model.objects.create_user(username='loc-passenger')
        UserProfile.objects.create(
            user=self.passenger, role=UserProfile.Role.PASSENGER
        )
        self.other_pilot = user_model.objects.create_user(username='other-loc-pilot')
        UserProfile.objects.create(user=self.other_pilot, role=UserProfile.Role.PILOT)

        self.bus = Bus.objects.create(
            registration_number='KA-34-A-4004', pilot=self.pilot
        )
        self.route = Route.objects.create(
            source_name='Bengaluru', destination_name='Ballari'
        )
        self.trip = Trip.objects.create(
            pilot=self.pilot, bus=self.bus, route=self.route, status=Trip.Status.ACTIVE
        )
        self.client = APIClient()

    def test_authenticated_pilot_submits_gps_and_persists_in_db(self):
        self.client.force_authenticate(self.pilot)
        response = self.client.post(
            '/api/trips/location/',
            {
                'trip_id': self.trip.id,
                'latitude': '13.340881',
                'longitude': '77.100616',
                'speed': '45.50',
                'bearing': '180.00',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['success'])

        self.trip.refresh_from_db()
        self.assertAlmostEqual(float(self.trip.current_latitude), 13.340881, places=5)
        self.assertAlmostEqual(float(self.trip.current_longitude), 77.100616, places=5)
        self.assertAlmostEqual(float(self.trip.current_speed), 45.50, places=2)
        self.assertAlmostEqual(float(self.trip.current_bearing), 180.00, places=2)
        self.assertIsNotNone(self.trip.last_gps_update)

    def test_different_pilot_cannot_submit_gps_for_trip(self):
        self.client.force_authenticate(self.other_pilot)
        response = self.client.post(
            '/api/trips/location/',
            {
                'trip_id': self.trip.id,
                'latitude': '13.340881',
                'longitude': '77.100616',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_passenger_cannot_submit_driver_gps(self):
        self.client.force_authenticate(self.passenger)
        response = self.client.post(
            '/api/trips/location/',
            {
                'trip_id': self.trip.id,
                'latitude': '13.340881',
                'longitude': '77.100616',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_location_submission_rejects_out_of_range_coordinates(self):
        self.client.force_authenticate(self.pilot)
        # Invalid latitude (> 90)
        r1 = self.client.post(
            '/api/trips/location/',
            {
                'trip_id': self.trip.id,
                'latitude': '95.000000',
                'longitude': '77.100616',
            },
            format='json',
        )
        self.assertEqual(r1.status_code, 400)

        # Invalid longitude (> 180)
        r2 = self.client.post(
            '/api/trips/location/',
            {
                'trip_id': self.trip.id,
                'latitude': '13.000000',
                'longitude': '195.000000',
            },
            format='json',
        )
        self.assertEqual(r2.status_code, 400)

    def test_gps_location_broadcasts_over_websocket(self):
        async def exercise_location_websocket():
            communicator = WebsocketCommunicator(
                application,
                '/ws/active-trips/',
                headers=[
                    (b'host', b'localhost'),
                    (b'origin', b'http://localhost'),
                ],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            await communicator.receive_json_from()  # Consume initial active_trips snapshot

            self.client.force_authenticate(self.pilot)
            response = await sync_to_async(
                self.client.post, thread_sensitive=True
            )(
                '/api/trips/location/',
                {
                    'trip_id': self.trip.id,
                    'latitude': '14.225126',
                    'longitude': '76.398003',
                    'speed': '55.00',
                    'bearing': '90.00',
                },
                format='json',
            )
            self.assertEqual(response.status_code, 200)

            event = await communicator.receive_json_from()
            self.assertEqual(event['event'], 'location_updated')
            self.assertEqual(event['trip_id'], self.trip.id)
            self.assertEqual(event['latitude'], '14.225126')
            self.assertEqual(event['longitude'], '76.398003')
            self.assertEqual(event['speed'], '55.00')
            self.assertEqual(event['bearing'], '90.00')
            await communicator.disconnect()

        async_to_sync(exercise_location_websocket)()
