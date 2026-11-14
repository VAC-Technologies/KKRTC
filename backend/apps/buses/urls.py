from django.urls import path

from apps.buses.views import BusListView

app_name = 'buses'

urlpatterns = [
    path('', BusListView.as_view(), name='bus-list'),
]
