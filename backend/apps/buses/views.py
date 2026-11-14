from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.buses.models import Bus
from apps.buses.serializers import BusSerializer


class BusListView(APIView):
    """
    GET: List active buses.
    Supports filtering by driver:
      - ?driver_id=<id>
      - ?driver_name=<name>
    Publicly accessible for Driver Dashboard testing workflow.
    """
    permission_classes = (permissions.AllowAny,)

    def get(self, request):
        queryset = Bus.objects.select_related('pilot').filter(is_active=True)

        driver_id = request.query_params.get('driver_id')
        if driver_id:
            try:
                queryset = queryset.filter(pilot_id=int(driver_id))
            except (ValueError, TypeError):
                return Response(
                    {'error': 'driver_id must be a valid integer.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        driver_name = request.query_params.get('driver_name')
        if driver_name:
            queryset = queryset.filter(pilot__username__iexact=driver_name.strip())

        serializer = BusSerializer(queryset, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)
