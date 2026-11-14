from rest_framework import serializers

from apps.buses.models import Bus


class BusSerializer(serializers.ModelSerializer):
    """
    Serializer for KKRTC Buses.
    Exposes driver information to support dependent dropdown filtering.
    """
    driver_id = serializers.IntegerField(source='pilot.id', read_only=True)
    driver_name = serializers.CharField(source='pilot.username', read_only=True)

    class Meta:
        model = Bus
        fields = (
            'id',
            'registration_number',
            'driver_id',
            'driver_name',
            'is_active',
        )
