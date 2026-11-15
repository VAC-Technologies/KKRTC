from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.trips.models import Trip
from apps.trips.permissions import IsAuthenticatedPilot
from apps.trips.serializers import (
    ActiveTripSerializer,
    EndTripSerializer,
    RecordTripLocationSerializer,
    StartTripSerializer,
)


def broadcast_active_trip_event(payload):
    from asgiref.sync import async_to_sync
    from channels.layers import get_channel_layer

    layer = get_channel_layer()
    if layer is not None:
        async_to_sync(layer.group_send)(
            'active_trips',
            {'type': payload['event'].replace('_', '.'), **payload},
        )


def trip_started_payload(trip):
    return {
        'event': 'trip_started',
        'trip_id': trip.id,
        'bus_registration': trip.bus.registration_number,
        'route': str(trip.route),
        'route_id': trip.route.route_id,
        'source_name': trip.route.source_name,
        'destination_name': trip.route.destination_name,
        'driver_name': trip.pilot.username,
        'status': trip.status,
    }


class StartTripView(APIView):
    permission_classes = (IsAuthenticated, IsAuthenticatedPilot)

    def post(self, request):
        serializer = StartTripSerializer(
            data=request.data, context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        try:
            with transaction.atomic():
                # Serialize concurrent starts by this pilot before checking status.
                type(request.user).objects.select_for_update().get(pk=request.user.pk)
                if Trip.objects.filter(
                    pilot=request.user, status=Trip.Status.ACTIVE
                ).exists():
                    raise ValidationError(
                        {'detail': 'This pilot already has an active trip.'}
                    )
                trip = Trip.objects.create(
                    pilot=request.user,
                    route=serializer.validated_data['route'],
                    bus=serializer.validated_data['bus'],
                    status=Trip.Status.ACTIVE,
                )
        except IntegrityError:
            # The conditional unique constraint is the final concurrency guard.
            return Response(
                {'detail': 'This pilot already has an active trip.'},
                status=status.HTTP_409_CONFLICT,
            )

        broadcast_active_trip_event(trip_started_payload(trip))

        return Response(
            {
                'trip_id': trip.id,
                'status': trip.status,
                'route': str(trip.route),
                'start_time': trip.start_time,
            },
            status=status.HTTP_201_CREATED,
        )


class EndTripView(APIView):
    permission_classes = (IsAuthenticated, IsAuthenticatedPilot)

    def post(self, request):
        serializer = EndTripSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        trip_id = serializer.validated_data['trip_id']

        with transaction.atomic():
            trip = Trip.objects.select_for_update().filter(pk=trip_id).first()
            if trip is None:
                return Response(
                    {'detail': 'Trip not found.'},
                    status=status.HTTP_404_NOT_FOUND,
                )
            if trip.pilot_id != request.user.id:
                return Response(
                    {'detail': 'Only the pilot who started this trip can end it.'},
                    status=status.HTTP_403_FORBIDDEN,
                )
            if trip.status != Trip.Status.ACTIVE:
                return Response(
                    {'detail': 'Only active trips can be ended.'},
                    status=status.HTTP_409_CONFLICT,
                )

            trip.status = Trip.Status.COMPLETED
            trip.end_time = timezone.now()
            trip.save(update_fields=('status', 'end_time'))

        broadcast_active_trip_event(
            {
                'event': 'trip_ended',
                'trip_id': trip.id,
                'status': trip.status,
            }
        )
        return Response(
            {
                'trip_id': trip.id,
                'status': trip.status,
                'end_time': trip.end_time,
            },
            status=status.HTTP_200_OK,
        )


class CurrentPilotActiveTripView(APIView):
    """
    Returns the active trip for the currently authenticated pilot, if any.
    """
    permission_classes = (IsAuthenticated, IsAuthenticatedPilot)

    def get(self, request):
        trip = (
            Trip.objects.filter(pilot=request.user, status=Trip.Status.ACTIVE)
            .select_related('route', 'bus')
            .first()
        )
        if not trip:
            return Response({'active_trip': None}, status=status.HTTP_200_OK)
        return Response(
            {'active_trip': ActiveTripSerializer(trip).data},
            status=status.HTTP_200_OK,
        )


class ActiveTripsView(APIView):
    permission_classes = (permissions.AllowAny,)

    def get(self, request):
        trips = Trip.objects.filter(status=Trip.Status.ACTIVE).select_related('route', 'bus')
        return Response(ActiveTripSerializer(trips, many=True).data)


class TripDetailView(APIView):
    permission_classes = (permissions.AllowAny,)

    def get(self, request, pk):
        trip = Trip.objects.select_related('route', 'bus').filter(pk=pk).first()
        if not trip:
            return Response({'detail': 'Trip not found.'}, status=status.HTTP_404_NOT_FOUND)
        return Response(ActiveTripSerializer(trip).data, status=status.HTTP_200_OK)


class RecordTripLocationView(APIView):
    """
    Submits live GPS coordinates from the authenticated pilot's device.
    Validates pilot ownership of the active trip, persists the latest coordinates,
    and broadcasts the update via Django Channels WebSocket.
    """
    permission_classes = (IsAuthenticated, IsAuthenticatedPilot)

    def post(self, request):
        serializer = RecordTripLocationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        trip_id = serializer.validated_data['trip_id']
        latitude = serializer.validated_data['latitude']
        longitude = serializer.validated_data['longitude']
        speed = serializer.validated_data.get('speed', 0.0)
        bearing = serializer.validated_data.get('bearing', 0.0)

        with transaction.atomic():
            trip = Trip.objects.select_for_update().select_related('bus', 'route').filter(pk=trip_id).first()
            if trip is None:
                return Response(
                    {'detail': 'Trip not found.'},
                    status=status.HTTP_404_NOT_FOUND,
                )
            if trip.pilot_id != request.user.id:
                return Response(
                    {'detail': 'Only the pilot who started this trip can submit location updates.'},
                    status=status.HTTP_403_FORBIDDEN,
                )
            if trip.status != Trip.Status.ACTIVE:
                return Response(
                    {'detail': 'Location updates can only be submitted for active trips.'},
                    status=status.HTTP_409_CONFLICT,
                )

            now = timezone.now()
            trip.current_latitude = latitude
            trip.current_longitude = longitude
            trip.current_speed = speed
            trip.current_bearing = bearing
            trip.last_gps_update = now
            trip.save(update_fields=(
                'current_latitude',
                'current_longitude',
                'current_speed',
                'current_bearing',
                'last_gps_update',
            ))

        location_payload = {
            'event': 'location_updated',
            'trip_id': trip.id,
            'bus_registration': trip.bus.registration_number,
            'route': str(trip.route),
            'latitude': str(latitude),
            'longitude': str(longitude),
            'speed': str(speed) if speed is not None else '0.0',
            'bearing': str(bearing) if bearing is not None else '0.0',
            'updated_at': now.isoformat(),
        }
        broadcast_active_trip_event(location_payload)

        return Response(
            {
                'success': True,
                'trip_id': trip.id,
                'latitude': str(latitude),
                'longitude': str(longitude),
                'speed': str(speed) if speed is not None else '0.0',
                'bearing': str(bearing) if bearing is not None else '0.0',
                'updated_at': now.isoformat(),
            },
            status=status.HTTP_200_OK,
        )
