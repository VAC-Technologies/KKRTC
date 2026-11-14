from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.buses.models import Bus

User = get_user_model()


class BusEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()

        # Driver 1
        self.driver1 = User.objects.create_user(username='Anil', first_name='Anil')
        self.profile1 = UserProfile.objects.create(
            user=self.driver1,
            role=UserProfile.Role.PILOT,
            phone_number='9876543210',
            is_authorized_pilot=True,
        )

        # Driver 2
        self.driver2 = User.objects.create_user(username='Basavaraj', first_name='Basavaraj')
        self.profile2 = UserProfile.objects.create(
            user=self.driver2,
            role=UserProfile.Role.PILOT,
            phone_number='9876543211',
            is_authorized_pilot=True,
        )

        # Buses
        self.bus1 = Bus.objects.create(
            registration_number='KA-35-F-1234',
            pilot=self.driver1,
            is_active=True,
        )
        self.bus2 = Bus.objects.create(
            registration_number='KA-34-A-5678',
            pilot=self.driver2,
            is_active=True,
        )
        self.inactive_bus = Bus.objects.create(
            registration_number='KA-34-A-9999',
            pilot=self.driver1,
            is_active=False,
        )

    def test_list_all_active_buses(self):
        response = self.client.get('/api/buses/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        regs = [b['registration_number'] for b in response.data]
        self.assertIn('KA-35-F-1234', regs)
        self.assertIn('KA-34-A-5678', regs)
        self.assertNotIn('KA-34-A-9999', regs)

    def test_filter_buses_by_driver_id(self):
        response = self.client.get(f'/api/buses/?driver_id={self.driver1.id}')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['registration_number'], 'KA-35-F-1234')
        self.assertEqual(response.data[0]['driver_name'], 'Anil')

    def test_filter_buses_by_driver_name(self):
        response = self.client.get('/api/buses/?driver_name=Basavaraj')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['registration_number'], 'KA-34-A-5678')
        self.assertEqual(response.data[0]['driver_name'], 'Basavaraj')

    def test_filter_buses_unknown_driver_returns_empty(self):
        response = self.client.get('/api/buses/?driver_name=UnknownDriver')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 0)

    def test_invalid_driver_id_returns_bad_request(self):
        response = self.client.get('/api/buses/?driver_id=not-an-int')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
