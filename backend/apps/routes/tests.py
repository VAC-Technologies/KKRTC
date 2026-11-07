from decimal import Decimal
from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.buses.models import Bus
from apps.routes.admin import RouteAdmin, StopInline
from apps.routes.models import Route, Stop
from apps.trips.models import Trip


class RouteManagementSystemTests(TestCase):
    """
    Complete test suite covering Route Creation, Via Stop Management,
    Admin Permissions, Validations, and Error Handling.
    """

    def setUp(self):
        self.user_model = get_user_model()

        # Admin / Staff user
        self.admin_user = self.user_model.objects.create_superuser(
            username='admin_officer',
            password='AdminPassword123!',
            email='admin@kkrtc.karnataka.gov.in',
        )

        # Regular passenger user
        self.passenger_user = self.user_model.objects.create_user(
            username='commuter_basava',
            password='PassengerPass123!',
        )
        UserProfile.objects.create(
            user=self.passenger_user,
            role=UserProfile.Role.PASSENGER,
        )

        # Pilot user
        self.pilot_user = self.user_model.objects.create_user(
            username='pilot_sharan',
            password='PilotPassword123!',
        )
        UserProfile.objects.create(
            user=self.pilot_user,
            role=UserProfile.Role.PILOT,
        )

        self.client = APIClient()

    # 1. ROUTE CREATION
    def test_admin_creates_route_with_multiple_via_stops_atomically(self):
        self.client.force_authenticate(user=self.admin_user)

        payload = {
            'route_id': 'R001',
            'source_name': 'Bengaluru',
            'source_latitude': '12.971599',
            'source_longitude': '77.594566',
            'destination_name': 'Ballari',
            'destination_latitude': '15.139393',
            'destination_longitude': '76.921448',
            'distance_km': '310.50',
            'is_active': True,
            'stops': [
                {
                    'stop_name': 'Tumakuru',
                    'latitude': '13.340881',
                    'longitude': '77.100601',
                    'sequence_order': 1,
                    'is_active': True,
                },
                {
                    'stop_name': 'Chitradurga',
                    'latitude': '14.230556',
                    'longitude': '76.399994',
                    'sequence_order': 2,
                    'is_active': True,
                },
                {
                    'stop_name': 'Vijayanagara',
                    'latitude': '15.274720',
                    'longitude': '76.389720',
                    'sequence_order': 3,
                    'is_active': True,
                },
            ],
        }

        response = self.client.post('/api/routes/', payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['route_id'], 'R001')
        self.assertEqual(response.data['source_name'], 'Bengaluru')
        self.assertEqual(response.data['destination_name'], 'Ballari')
        self.assertEqual(response.data['stops_count'], 3)
        self.assertEqual(len(response.data['stops']), 3)

        # Verify DB records
        route = Route.objects.get(route_id='R001')
        self.assertEqual(route.stops.count(), 3)
        stop_names = list(route.stops.order_by('sequence_order').values_list('stop_name', flat=True))
        self.assertEqual(stop_names, ['Tumakuru', 'Chitradurga', 'Vijayanagara'])

    # 2. DUPLICATE ROUTE ID REJECTION
    def test_duplicate_route_id_rejection(self):
        Route.objects.create(
            route_id='R001',
            source_name='Bengaluru',
            destination_name='Ballari',
        )

        self.client.force_authenticate(user=self.admin_user)
        payload = {
            'route_id': 'R001',  # Duplicate!
            'source_name': 'Bengaluru',
            'destination_name': 'Hubballi',
        }

        response = self.client.post('/api/routes/', payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('route_id', response.data)
        self.assertIn('already exists', str(response.data['route_id']))

    # 3. ROUTE RETRIEVAL (BY PK & ROUTE_ID)
    def test_route_retrieval_by_pk_and_route_id(self):
        route = Route.objects.create(
            route_id='R105',
            source_name='Kalaburagi',
            destination_name='Raichur',
            distance_km=Decimal('142.00'),
        )
        Stop.objects.create(
            route=route,
            stop_name='Shahabad',
            latitude=Decimal('17.133333'),
            longitude=Decimal('76.933333'),
            sequence_order=1,
        )

        self.client.force_authenticate(user=self.passenger_user)

        # Retrieve by Route ID string
        resp1 = self.client.get('/api/routes/R105/')
        self.assertEqual(resp1.status_code, status.HTTP_200_OK)
        self.assertEqual(resp1.data['route_id'], 'R105')
        self.assertEqual(resp1.data['stops_count'], 1)

        # Retrieve by integer primary key
        resp2 = self.client.get(f'/api/routes/{route.id}/')
        self.assertEqual(resp2.status_code, status.HTTP_200_OK)
        self.assertEqual(resp2.data['route_id'], 'R105')

    # 4. ROUTE LISTING & FILTERING
    def test_route_list_with_search_and_filters(self):
        r1 = Route.objects.create(route_id='R201', source_name='Kalaburagi', destination_name='Bidar')
        r2 = Route.objects.create(route_id='R202', source_name='Ballari', destination_name='Hosapete')
        r3 = Route.objects.create(route_id='R203', source_name='Yadgir', destination_name='Shahapur', is_active=False)

        self.client.force_authenticate(user=self.passenger_user)

        # All routes
        resp = self.client.get('/api/routes/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 3)

        # Search by term
        resp_search = self.client.get('/api/routes/?search=Ballari')
        self.assertEqual(resp_search.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp_search.data), 1)
        self.assertEqual(resp_search.data[0]['route_id'], 'R202')

        # Filter by is_active=true
        resp_active = self.client.get('/api/routes/?is_active=true')
        self.assertEqual(resp_active.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp_active.data), 2)

    # 5. ROUTE UPDATE (PUT & PATCH)
    def test_route_updates_by_admin(self):
        route = Route.objects.create(
            route_id='R301',
            source_name='Kalaburagi',
            destination_name='Solapur',
            distance_km=Decimal('110.00'),
        )

        self.client.force_authenticate(user=self.admin_user)

        # Partial update distance and destination
        patch_resp = self.client.patch(
            f'/api/routes/{route.route_id}/',
            {'distance_km': '115.75', 'destination_name': 'Solapur Central'},
            format='json',
        )
        self.assertEqual(patch_resp.status_code, status.HTTP_200_OK)
        self.assertEqual(patch_resp.data['destination_name'], 'Solapur Central')
        self.assertEqual(Decimal(str(patch_resp.data['distance_km'])), Decimal('115.75'))

        route.refresh_from_db()
        self.assertEqual(route.destination_name, 'Solapur Central')

    # 6. ROUTE DELETION
    def test_route_deletion_by_admin(self):
        route = Route.objects.create(
            route_id='R401',
            source_name='Hubballi',
            destination_name='Dharwad',
        )

        self.client.force_authenticate(user=self.admin_user)
        del_resp = self.client.delete(f'/api/routes/{route.route_id}/')
        self.assertEqual(del_resp.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Route.objects.filter(route_id='R401').exists())

    # 7. ROUTE DELETION SAFEGUARD WITH ACTIVE TRIP
    def test_route_deletion_safeguard_when_trip_is_active(self):
        route = Route.objects.create(
            route_id='R501',
            source_name='Ballari',
            destination_name='Siruguppa',
        )
        bus = Bus.objects.create(
            registration_number='KA-34-KK-9999',
            pilot=self.pilot_user,
        )
        Trip.objects.create(
            pilot=self.pilot_user,
            bus=bus,
            route=route,
            status=Trip.Status.ACTIVE,
        )

        self.client.force_authenticate(user=self.admin_user)
        del_resp = self.client.delete(f'/api/routes/{route.route_id}/')
        self.assertEqual(del_resp.status_code, status.HTTP_409_CONFLICT)
        self.assertIn('active trip', del_resp.data['detail'].lower())
        self.assertTrue(Route.objects.filter(route_id='R501').exists())

    # 8. VIA STOPS RETRIEVAL IN CORRECT SEQUENCE
    def test_ordered_stops_retrieval(self):
        route = Route.objects.create(
            route_id='R601',
            source_name='Ballari',
            destination_name='Bengaluru',
        )
        # Create out of order in database
        Stop.objects.create(route=route, stop_name='Chitradurga', latitude=Decimal('14.23'), longitude=Decimal('76.40'), sequence_order=2)
        Stop.objects.create(route=route, stop_name='Tumakuru', latitude=Decimal('13.34'), longitude=Decimal('77.10'), sequence_order=1)
        Stop.objects.create(route=route, stop_name='Sira', latitude=Decimal('13.74'), longitude=Decimal('76.90'), sequence_order=3)

        self.client.force_authenticate(user=self.passenger_user)
        resp = self.client.get(f'/api/routes/{route.route_id}/stops/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 3)

        # Must be in correct sequence: Tumakuru (1), Chitradurga (2), Sira (3)
        sequences = [s['sequence_order'] for s in resp.data]
        names = [s['stop_name'] for s in resp.data]
        self.assertEqual(sequences, [1, 2, 3])
        self.assertEqual(names, ['Tumakuru', 'Chitradurga', 'Sira'])

    # 9. ADD SINGLE STOP TO ROUTE
    def test_add_single_stop_to_route(self):
        route = Route.objects.create(
            route_id='R701',
            source_name='Vijayapura',
            destination_name='Bagalkote',
        )

        self.client.force_authenticate(user=self.admin_user)
        stop_payload = {
            'stop_name': 'Almatti',
            'latitude': '16.331111',
            'longitude': '75.892778',
            'sequence_order': 1,
            'is_active': True,
        }
        resp = self.client.post(f'/api/routes/{route.route_id}/stops/', stop_payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['stop_name'], 'Almatti')
        self.assertEqual(route.stops.count(), 1)

    # 10. DUPLICATE STOP SEQUENCE REJECTION
    def test_duplicate_stop_sequence_rejection(self):
        route = Route.objects.create(
            route_id='R801',
            source_name='Shivamogga',
            destination_name='Bhadravathi',
        )
        Stop.objects.create(
            route=route,
            stop_name='Nidige',
            latitude=Decimal('13.88'),
            longitude=Decimal('75.64'),
            sequence_order=1,
        )

        self.client.force_authenticate(user=self.admin_user)
        duplicate_seq_payload = {
            'stop_name': 'Holehonnur Cross',
            'latitude': '13.90',
            'longitude': '75.66',
            'sequence_order': 1,  # Duplicate sequence!
        }
        resp = self.client.post(f'/api/routes/{route.route_id}/stops/', duplicate_seq_payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('sequence_order', resp.data)

    # 11. INVALID COORDINATE REJECTION
    def test_invalid_latitude_rejection(self):
        self.client.force_authenticate(user=self.admin_user)

        # Latitude > 90.0
        payload = {
            'route_id': 'R901',
            'source_name': 'Test Origin',
            'destination_name': 'Test Destination',
            'source_latitude': '95.500000',  # Invalid!
            'source_longitude': '77.000000',
        }
        resp = self.client.post('/api/routes/', payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('source_latitude', resp.data)

        # Stop with latitude < -90.0
        route = Route.objects.create(route_id='R902', source_name='A', destination_name='B')
        stop_payload = {
            'stop_name': 'Invalid Stop',
            'latitude': '-99.999999',  # Invalid!
            'longitude': '75.000000',
            'sequence_order': 1,
        }
        stop_resp = self.client.post(f'/api/routes/{route.route_id}/stops/', stop_payload, format='json')
        self.assertEqual(stop_resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('latitude', stop_resp.data)

    def test_invalid_longitude_rejection(self):
        self.client.force_authenticate(user=self.admin_user)

        # Longitude > 180.0
        payload = {
            'route_id': 'R903',
            'source_name': 'Test Origin',
            'destination_name': 'Test Destination',
            'source_latitude': '15.000000',
            'source_longitude': '195.000000',  # Invalid!
        }
        resp = self.client.post('/api/routes/', payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('source_longitude', resp.data)

    # 12. UNAUTHORIZED / NON-ADMIN PERMISSION CHECKS
    def test_unauthenticated_user_cannot_create_or_modify_route(self):
        # No credentials provided
        payload = {'route_id': 'R999', 'source_name': 'A', 'destination_name': 'B'}
        post_resp = self.client.post('/api/routes/', payload, format='json')
        self.assertEqual(post_resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_passenger_and_pilot_cannot_modify_routes(self):
        route = Route.objects.create(route_id='R998', source_name='A', destination_name='B')

        # Passenger attempts to create route
        self.client.force_authenticate(user=self.passenger_user)
        resp1 = self.client.post('/api/routes/', {'route_id': 'R002', 'source_name': 'A', 'destination_name': 'B'}, format='json')
        self.assertEqual(resp1.status_code, status.HTTP_403_FORBIDDEN)

        # Pilot attempts to delete route
        self.client.force_authenticate(user=self.pilot_user)
        resp2 = self.client.delete(f'/api/routes/{route.route_id}/')
        self.assertEqual(resp2.status_code, status.HTTP_403_FORBIDDEN)

    def test_passenger_can_read_routes_and_stops(self):
        route = Route.objects.create(route_id='R997', source_name='A', destination_name='B')
        Stop.objects.create(route=route, stop_name='Via Stop 1', latitude=Decimal('15.0'), longitude=Decimal('76.0'), sequence_order=1)

        self.client.force_authenticate(user=self.passenger_user)
        list_resp = self.client.get('/api/routes/')
        self.assertEqual(list_resp.status_code, status.HTTP_200_OK)

        detail_resp = self.client.get(f'/api/routes/{route.route_id}/')
        self.assertEqual(detail_resp.status_code, status.HTTP_200_OK)

        stops_resp = self.client.get(f'/api/routes/{route.route_id}/stops/')
        self.assertEqual(stops_resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(stops_resp.data), 1)

    def test_unauthenticated_public_can_read_routes_and_stops(self):
        route = Route.objects.create(route_id='R996', source_name='Bengaluru', destination_name='Ballari')
        Stop.objects.create(route=route, stop_name='Tumakuru', sequence_order=1)

        # Explicitly unauthenticated client
        self.client.force_authenticate(user=None)
        list_resp = self.client.get('/api/routes/')
        self.assertEqual(list_resp.status_code, status.HTTP_200_OK)
        route_item = next(r for r in list_resp.data if r['route_id'] == 'R996')
        self.assertEqual(len(route_item['stops']), 1)
        self.assertEqual(route_item['stops'][0]['stop_name'], 'Tumakuru')

        # Test search by via stop name
        search_resp = self.client.get('/api/routes/?search=Tumakuru')
        self.assertEqual(search_resp.status_code, status.HTTP_200_OK)
        self.assertTrue(any(r['route_id'] == 'R996' for r in search_resp.data))

        # Test empty search results
        empty_resp = self.client.get('/api/routes/?search=NonExistentPlaceXYZ')
        self.assertEqual(empty_resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(empty_resp.data), 0)

        # Test invalid lookup returns 404
        nf_resp = self.client.get('/api/routes/INVALID999/')
        self.assertEqual(nf_resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_auto_resolve_coordinates_when_omitted(self):
        # Admin creates route and stop without manual coordinates
        route = Route.objects.create(
            route_id='R995',
            source_name='Bengaluru',
            destination_name='Ballari',
        )
        self.assertIsNotNone(route.source_latitude)
        self.assertIsNotNone(route.source_longitude)
        self.assertIsNotNone(route.destination_latitude)
        self.assertIsNotNone(route.destination_longitude)

        stop = Stop.objects.create(
            route=route,
            stop_name='Tumakuru',
            sequence_order=1,
        )
        self.assertIsNotNone(stop.latitude)
        self.assertIsNotNone(stop.longitude)

    def test_location_suggestions_autocomplete(self):
        """
        Tests that /api/routes/locations/suggestions/ returns From, To, and Via stops
        matching a partial query without exposing latitude or longitude.
        """
        route = Route.objects.create(
            route_id='R-AUTO-1',
            source_name='Kalaburagi',
            destination_name='Ballari',
        )
        Stop.objects.create(
            route=route,
            stop_name='Hospet Station',
            sequence_order=1,
        )

        # Unauthenticated request with partial query 'bal'
        self.client.force_authenticate(user=None)
        response = self.client.get('/api/routes/locations/suggestions/?q=bal')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        names = [item['name'] for item in response.data]
        self.assertIn('Ballari', names)

        # Partial query for via stop 'hosp'
        response_via = self.client.get('/api/routes/locations/suggestions/?q=hosp')
        self.assertEqual(response_via.status_code, status.HTTP_200_OK)
        via_names = [item['name'] for item in response_via.data]
        self.assertIn('Hospet Station', via_names)

        # Ensure no latitude or longitude fields exist in suggestions response
        for item in response_via.data:
            self.assertNotIn('latitude', item)
            self.assertNotIn('longitude', item)

    # 13. DJANGO ADMIN REGISTRATION & INLINE VERIFICATION
    def test_django_admin_registration_and_inlines(self):
        from django.contrib.admin.sites import site
        self.assertIn(Route, site._registry)
        self.assertIn(Stop, site._registry)

        route_admin = site._registry[Route]
        self.assertIsInstance(route_admin, RouteAdmin)
        self.assertTrue(any(issubclass(inline, StopInline) for inline in route_admin.inlines))
        self.assertIn('route_id', route_admin.search_fields)
        self.assertIn('source_name', route_admin.search_fields)
        self.assertIn('destination_name', route_admin.search_fields)
