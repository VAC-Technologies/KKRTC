from django.urls import path

from apps.trips.views import (
    ActiveTripsView,
    EndTripView,
    RecordTripLocationView,
    StartTripView,
    TripDetailView,
)

urlpatterns = [
    path('start/', StartTripView.as_view(), name='trip-start'),
    path('end/', EndTripView.as_view(), name='trip-end'),
    path('active/', ActiveTripsView.as_view(), name='active-trips'),
    path('location/', RecordTripLocationView.as_view(), name='trip-location'),
    path('<int:pk>/', TripDetailView.as_view(), name='trip-detail'),
]
