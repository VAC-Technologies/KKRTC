from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

from apps.trips.models import Trip


class ActiveTripsConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        await self.channel_layer.group_add('active_trips', self.channel_name)
        await self.accept()
        await self.send_json(
            {
                'event': 'active_trips',
                'trips': await self.get_active_trips(),
            }
        )

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard('active_trips', self.channel_name)

    async def trip_started(self, event):
        await self.send_json(
            {
                'event': event['event'],
                'trip_id': event['trip_id'],
                'bus_registration': event.get('bus_registration', ''),
                'route': event['route'],
                'route_id': event.get('route_id', ''),
                'source_name': event.get('source_name', ''),
                'destination_name': event.get('destination_name', ''),
                'driver_name': event.get('driver_name', ''),
                'status': event['status'],
            }
        )

    async def trip_ended(self, event):
        await self.send_json(
            {
                'event': event['event'],
                'trip_id': event['trip_id'],
                'status': event['status'],
            }
        )

    async def location_updated(self, event):
        await self.send_json(
            {
                'event': event['event'],
                'trip_id': event['trip_id'],
                'bus_registration': event.get('bus_registration', ''),
                'route': event.get('route', ''),
                'latitude': event['latitude'],
                'longitude': event['longitude'],
                'speed': event.get('speed', '0.0'),
                'bearing': event.get('bearing', '0.0'),
                'updated_at': event.get('updated_at'),
            }
        )

    @database_sync_to_async
    def get_active_trips(self):
        trips = Trip.objects.filter(status=Trip.Status.ACTIVE).select_related('route', 'bus', 'pilot')
        return [
            {
                'trip_id': trip.id,
                'bus_registration': trip.bus.registration_number,
                'route': str(trip.route),
                'route_id': trip.route.route_id,
                'source_name': trip.route.source_name,
                'destination_name': trip.route.destination_name,
                'driver_name': trip.pilot.username,
                'status': trip.status,
                'latitude': str(trip.current_latitude) if trip.current_latitude is not None else None,
                'longitude': str(trip.current_longitude) if trip.current_longitude is not None else None,
                'speed': str(trip.current_speed) if trip.current_speed is not None else '0.0',
                'bearing': str(trip.current_bearing) if trip.current_bearing is not None else '0.0',
                'updated_at': trip.last_gps_update.isoformat() if trip.last_gps_update else None,
            }
            for trip in trips
        ]
