from django.db.models import Q
from rest_framework import status
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.routes.models import Route, Stop
from apps.routes.permissions import IsAdminOrReadOnly
from apps.routes.serializers import (
    RouteDetailSerializer,
    RouteListSerializer,
    StopSerializer,
)


def get_route_or_404(lookup):
    """
    Retrieves a Route instance by either integer primary key (ID)
    or unique string Route ID (e.g. 'R001', 'KK-01').
    """
    lookup_str = str(lookup).strip()
    route = None
    if lookup_str.isdigit():
        route = Route.objects.filter(pk=int(lookup_str)).first()
    if route is None:
        route = Route.objects.filter(route_id__iexact=lookup_str).first()
    if route is None:
        raise NotFound(detail=f'Route "{lookup}" not found.')
    return route


class RouteListCreateView(APIView):
    """
    GET: List all routes with optional search and filtering (authenticated users).
    POST: Create a new route with optional nested Via stops (admin only).
    """
    permission_classes = (IsAdminOrReadOnly,)

    def get(self, request):
        queryset = Route.objects.prefetch_related('stops').all()

        search_query = request.query_params.get('search', '').strip()
        if search_query:
            queryset = queryset.filter(
                Q(route_id__icontains=search_query) |
                Q(source_name__icontains=search_query) |
                Q(destination_name__icontains=search_query) |
                Q(stops__stop_name__icontains=search_query)
            ).distinct()

        source = request.query_params.get('source', '').strip()
        if source:
            queryset = queryset.filter(
                Q(source_name__icontains=source) |
                Q(stops__stop_name__icontains=source)
            ).distinct()

        destination = request.query_params.get('destination', '').strip()
        if destination:
            queryset = queryset.filter(
                Q(destination_name__icontains=destination) |
                Q(stops__stop_name__icontains=destination)
            ).distinct()

        is_active = request.query_params.get('is_active')
        if is_active is not None:
            active_bool = is_active.lower() in ('true', '1', 'yes')
            queryset = queryset.filter(is_active=active_bool)

        serializer = RouteListSerializer(queryset, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def post(self, request):
        serializer = RouteDetailSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        route = serializer.save()
        return Response(
            RouteDetailSerializer(route).data,
            status=status.HTTP_201_CREATED,
        )


class RouteDetailView(APIView):
    """
    GET: Retrieve full details of a route and its ordered Via stops.
    PUT/PATCH: Update route details and/or replace nested Via stops (admin only).
    DELETE: Delete route with active trip safeguards (admin only).
    """
    permission_classes = (IsAdminOrReadOnly,)

    def get(self, request, lookup):
        route = get_route_or_404(lookup)
        serializer = RouteDetailSerializer(route)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def put(self, request, lookup):
        route = get_route_or_404(lookup)
        serializer = RouteDetailSerializer(route, data=request.data)
        serializer.is_valid(raise_exception=True)
        updated_route = serializer.save()
        return Response(RouteDetailSerializer(updated_route).data, status=status.HTTP_200_OK)

    def patch(self, request, lookup):
        route = get_route_or_404(lookup)
        serializer = RouteDetailSerializer(route, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        updated_route = serializer.save()
        return Response(RouteDetailSerializer(updated_route).data, status=status.HTTP_200_OK)

    def delete(self, request, lookup):
        route = get_route_or_404(lookup)
        # Safeguard: Do not allow deletion if there are active trips running on this route
        if hasattr(route, 'trips') and route.trips.filter(status='ACTIVE').exists():
            return Response(
                {'detail': f'Cannot delete route "{route.route_id}" because an active trip is currently in progress on it.'},
                status=status.HTTP_409_CONFLICT,
            )
        route.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class RouteStopsView(APIView):
    """
    GET: Retrieve the ordered sequence of Via stops for a given route.
    POST: Append a new Via stop to the route (admin only).
    """
    permission_classes = (IsAdminOrReadOnly,)

    def get(self, request, lookup):
        route = get_route_or_404(lookup)
        stops = route.stops.order_by('sequence_order', 'id')
        serializer = StopSerializer(stops, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def post(self, request, lookup):
        route = get_route_or_404(lookup)
        serializer = StopSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        seq = serializer.validated_data.get('sequence_order')
        if seq is not None and route.stops.filter(sequence_order=seq).exists():
            raise ValidationError(
                {'sequence_order': f'A stop with sequence order {seq} already exists on this route.'}
            )
        stop = serializer.save(route=route)
        return Response(StopSerializer(stop).data, status=status.HTTP_201_CREATED)


class RouteStopDetailView(APIView):
    """
    GET/PUT/PATCH/DELETE an individual Via stop on a given route.
    """
    permission_classes = (IsAdminOrReadOnly,)

    def get_stop(self, lookup, stop_id):
        route = get_route_or_404(lookup)
        stop = route.stops.filter(pk=stop_id).first()
        if stop is None:
            raise NotFound(detail=f'Stop #{stop_id} not found on route "{route.route_id}".')
        return stop

    def get(self, request, lookup, stop_id):
        stop = self.get_stop(lookup, stop_id)
        return Response(StopSerializer(stop).data, status=status.HTTP_200_OK)

    def put(self, request, lookup, stop_id):
        stop = self.get_stop(lookup, stop_id)
        serializer = StopSerializer(stop, data=request.data)
        serializer.is_valid(raise_exception=True)
        updated_stop = serializer.save()
        return Response(StopSerializer(updated_stop).data, status=status.HTTP_200_OK)

    def patch(self, request, lookup, stop_id):
        stop = self.get_stop(lookup, stop_id)
        serializer = StopSerializer(stop, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        updated_stop = serializer.save()
        return Response(StopSerializer(updated_stop).data, status=status.HTTP_200_OK)

    def delete(self, request, lookup, stop_id):
        stop = self.get_stop(lookup, stop_id)
        stop.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class LocationSuggestionsView(APIView):
    """
    GET: Returns real-time autocomplete suggestions for bus stops and terminus stations.
    Searches across route sources, destinations, and intermediate Via stops.
    Supports partial and case-insensitive matching.
    Omits latitude and longitude from user payloads.
    """
    permission_classes = (IsAdminOrReadOnly,)

    def get(self, request):
        query = request.query_params.get('q', '').strip()
        suggestions_map = {}

        # 1. Query Route Endpoints (Origin / Destination)
        routes = Route.objects.filter(is_active=True)
        if query:
            routes = routes.filter(
                Q(source_name__icontains=query) | Q(destination_name__icontains=query)
            )

        for route in routes:
            s_name = route.source_name.strip()
            d_name = route.destination_name.strip()

            if not query or query.lower() in s_name.lower():
                entry = suggestions_map.setdefault(
                    s_name.title(),
                    {
                        'name': s_name.title(),
                        'type': 'Bus Station / Origin',
                        'routes': [],
                    },
                )
                if route.route_id not in entry['routes']:
                    entry['routes'].append(route.route_id)

            if not query or query.lower() in d_name.lower():
                entry = suggestions_map.setdefault(
                    d_name.title(),
                    {
                        'name': d_name.title(),
                        'type': 'Bus Station / Destination',
                        'routes': [],
                    },
                )
                if route.route_id not in entry['routes']:
                    entry['routes'].append(route.route_id)

        # 2. Query Intermediate Via Stops
        stops = Stop.objects.filter(is_active=True).select_related('route')
        if query:
            stops = stops.filter(stop_name__icontains=query)

        for stop in stops:
            stop_title = stop.stop_name.strip().title()
            if stop_title in suggestions_map:
                if 'Via Stop' not in suggestions_map[stop_title]['type']:
                    suggestions_map[stop_title]['type'] += ' & Via Stop'
                if stop.route.route_id not in suggestions_map[stop_title]['routes']:
                    suggestions_map[stop_title]['routes'].append(stop.route.route_id)
            else:
                suggestions_map[stop_title] = {
                    'name': stop_title,
                    'type': 'Via Stop',
                    'routes': [stop.route.route_id],
                }

        results = list(suggestions_map.values())
        # Sort so exact matches or prefixes come first, then alphabetical
        results.sort(
            key=lambda x: (
                0 if query and x['name'].lower().startswith(query.lower()) else 1,
                x['name'],
            )
        )

        return Response(results, status=status.HTTP_200_OK)
