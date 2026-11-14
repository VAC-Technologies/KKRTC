from decimal import Decimal
from rest_framework import serializers

from apps.buses.models import Bus
from apps.routes.models import Route
from apps.trips.models import Trip


class RouteRelatedField(serializers.PrimaryKeyRelatedField):
    """
    Accepts either an integer primary key or a business route_id (e.g. '001', 'KKRTC-001').
    """
    def to_internal_value(self, data):
        val = str(data).strip()
        if val.isdigit():
            try:
                return super().to_internal_value(int(val))
            except serializers.ValidationError:
                pass
        route = Route.objects.filter(route_id__iexact=val, is_active=True).first()
        if route:
            return route
        raise serializers.ValidationError(f'Route "{data}" does not exist or is inactive.')


class StartTripSerializer(serializers.Serializer):
    route_id = RouteRelatedField(
        source='route', queryset=Route.objects.filter(is_active=True)
    )
    bus_id = serializers.PrimaryKeyRelatedField(
        source='bus', queryset=Bus.objects.filter(is_active=True)
    )

    def validate(self, attrs):
        pilot = self.context['request'].user
        if attrs['bus'].pilot_id != pilot.id:
            raise serializers.ValidationError(
                {'bus_id': 'This bus is not assigned to the authenticated pilot.'}
            )
        return attrs


class EndTripSerializer(serializers.Serializer):
    trip_id = serializers.IntegerField(min_value=1)


class RecordTripLocationSerializer(serializers.Serializer):
    trip_id = serializers.IntegerField(min_value=1)
    latitude = serializers.DecimalField(
        max_digits=9,
        decimal_places=6,
        min_value=Decimal('-90.0'),
        max_value=Decimal('90.0'),
    )
    longitude = serializers.DecimalField(
        max_digits=9,
        decimal_places=6,
        min_value=Decimal('-180.0'),
        max_value=Decimal('180.0'),
    )
    speed = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=Decimal('0.0'),
        required=False,
        allow_null=True,
        default=Decimal('0.0'),
    )
    bearing = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=Decimal('0.0'),
        max_value=Decimal('360.0'),
        required=False,
        allow_null=True,
        default=Decimal('0.0'),
    )


class ActiveTripSerializer(serializers.ModelSerializer):
    route = serializers.SerializerMethodField()
    bus_registration = serializers.CharField(
        source='bus.registration_number', read_only=True
    )

    class Meta:
        model = Trip
        fields = (
            'id',
            'route',
            'status',
            'start_time',
            'bus_registration',
            'current_latitude',
            'current_longitude',
            'current_speed',
            'current_bearing',
            'last_gps_update',
        )

    def get_route(self, trip):
        return str(trip.route)
