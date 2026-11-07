from django.urls import path

from apps.routes.views import (
    RouteDetailView,
    RouteListCreateView,
    RouteStopDetailView,
    RouteStopsView,
)

app_name = 'routes'

urlpatterns = [
    path('', RouteListCreateView.as_view(), name='route-list-create'),
    path('<str:lookup>/', RouteDetailView.as_view(), name='route-detail'),
    path('<str:lookup>/stops/', RouteStopsView.as_view(), name='route-stops'),
    path('<str:lookup>/stops/<int:stop_id>/', RouteStopDetailView.as_view(), name='route-stop-detail'),
]
