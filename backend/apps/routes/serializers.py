from decimal import Decimal
from django.db import transaction
from rest_framework import serializers

from apps.routes.models import Route, Stop


class StopSerializer(serializers.ModelSerializer):
    """
    Serializer for intermediate Via stops with optional coordinate inputs
    and strict sequence validation. Coordinates are auto-resolved if omitted.
    """
    latitude = serializers.DecimalField(
        max_digits=9,
        decimal_places=6,
        required=False,
        allow_null=True,
    )
    longitude = serializers.DecimalField(
        max_digits=9,
        decimal_places=6,
        required=False,
        allow_null=True,
    )
    class Meta:
        model = Stop
        fields = (
            'id',
            'stop_name',
            'latitude',
            'longitude',
            'sequence_order',
            'is_active',
            'created_at',
            'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_latitude(self, value):
        if value is not None:
            if value < Decimal('-90.0') or value > Decimal('90.0'):
                raise serializers.ValidationError('Latitude must be between -90.0 and 90.0 degrees.')
        return value

    def validate_longitude(self, value):
        if value is not None:
            if value < Decimal('-180.0') or value > Decimal('180.0'):
                raise serializers.ValidationError('Longitude must be between -180.0 and 180.0 degrees.')
        return value

    def validate_sequence_order(self, value):
        if value is not None and value < 1:
            raise serializers.ValidationError('Sequence order must be 1 or greater.')
        return value

    def validate_stop_name(self, value):
        val = value.strip()
        if not val:
            raise serializers.ValidationError('Stop name cannot be blank.')
        return val


class RouteDetailSerializer(serializers.ModelSerializer):
    """
    Comprehensive Route serializer including nested Via stops.
    Supports atomic nested creation and update of routes with multiple stops.
    """
    stops = StopSerializer(many=True, required=False)
    stops_count = serializers.IntegerField(source='stops.count', read_only=True)

    class Meta:
        model = Route
        fields = (
            'id',
            'route_id',
            'source_name',
            'source_latitude',
            'source_longitude',
            'destination_name',
            'destination_latitude',
            'destination_longitude',
            'distance_km',
            'is_active',
            'stops_count',
            'stops',
            'created_at',
            'updated_at',
        )
        read_only_fields = ('id', 'stops_count', 'created_at', 'updated_at')

    def validate_route_id(self, value):
        val = value.strip()
        if not val:
            raise serializers.ValidationError('Route ID cannot be empty.')
        qs = Route.objects.filter(route_id__iexact=val)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError('A route with this Route ID already exists.')
        return val

    def validate_source_name(self, value):
        val = value.strip()
        if not val:
            raise serializers.ValidationError('Starting location (From) cannot be blank.')
        return val

    def validate_destination_name(self, value):
        val = value.strip()
        if not val:
            raise serializers.ValidationError('Destination location (To) cannot be blank.')
        return val

    def validate_source_latitude(self, value):
        if value is not None and (value < Decimal('-90.0') or value > Decimal('90.0')):
            raise serializers.ValidationError('Source latitude must be between -90.0 and 90.0 degrees.')
        return value

    def validate_source_longitude(self, value):
        if value is not None and (value < Decimal('-180.0') or value > Decimal('180.0')):
            raise serializers.ValidationError('Source longitude must be between -180.0 and 180.0 degrees.')
        return value

    def validate_destination_latitude(self, value):
        if value is not None and (value < Decimal('-90.0') or value > Decimal('90.0')):
            raise serializers.ValidationError('Destination latitude must be between -90.0 and 90.0 degrees.')
        return value

    def validate_destination_longitude(self, value):
        if value is not None and (value < Decimal('-180.0') or value > Decimal('180.0')):
            raise serializers.ValidationError('Destination longitude must be between -180.0 and 180.0 degrees.')
        return value

    def validate_stops(self, stops):
        """
        Validate that sequence orders are unique and ascending.
        """
        if stops:
            seen_sequences = set()
            for stop in stops:
                seq = stop.get('sequence_order')
                if seq in seen_sequences:
                    raise serializers.ValidationError(
                        f'Duplicate stop sequence {seq} detected. Each via stop must have a unique sequence order.'
                    )
                seen_sequences.add(seq)
        return stops

    def create(self, validated_data):
        stops_data = validated_data.pop('stops', None)
        with transaction.atomic():
            route = Route.objects.create(**validated_data)
            if stops_data:
                for stop_dict in stops_data:
                    Stop.objects.create(route=route, **stop_dict)
            return route

    def update(self, instance, validated_data):
        stops_data = validated_data.pop('stops', None)
        with transaction.atomic():
            for attr, val in validated_data.items():
                setattr(instance, attr, val)
            instance.save()

            if stops_data is not None:
                instance.stops.all().delete()
                for stop_dict in stops_data:
                    Stop.objects.create(route=instance, **stop_dict)
            return instance


class RouteListSerializer(serializers.ModelSerializer):
    """
    Lightweight serializer for listing routes efficiently, including intermediate via stops.
    """
    stops = StopSerializer(many=True, read_only=True)
    stops_count = serializers.IntegerField(source='stops.count', read_only=True)

    class Meta:
        model = Route
        fields = (
            'id',
            'route_id',
            'source_name',
            'source_latitude',
            'source_longitude',
            'destination_name',
            'destination_latitude',
            'destination_longitude',
            'distance_km',
            'is_active',
            'stops_count',
            'stops',
            'created_at',
        )
