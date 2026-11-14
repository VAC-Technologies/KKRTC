import sys
from decimal import Decimal
from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.db import transaction
from apps.accounts.models import UserProfile
from apps.buses.models import Bus
from apps.routes.models import Route, Stop

User = get_user_model()

class Command(BaseCommand):
    help = 'Seeds initial pilot, bus, and route data for KKRTC cloud deployment and two-phone testing.'

    def handle(self, *args, **options):
        self.stdout.write('Seeding KKRTC initial data...')
        with transaction.atomic():
            # 1. Pilot: Anil
            pilot_user, created = User.objects.get_or_create(
                username='Anil',
                defaults={
                    'first_name': 'Anil',
                    'last_name': 'Kumar',
                    'is_active': True,
                }
            )
            if created:
                self.stdout.write(self.style.SUCCESS(f'Created User: {pilot_user.username}'))
            else:
                self.stdout.write(f'User {pilot_user.username} already exists')

            profile, prof_created = UserProfile.objects.get_or_create(
                user=pilot_user,
                defaults={
                    'role': UserProfile.Role.PILOT,
                    'phone_number': '9876543210',
                    'badge_number': 'KKRTC-P-4401',
                    'is_authorized_pilot': True,
                }
            )
            if not prof_created:
                profile.role = UserProfile.Role.PILOT
                profile.phone_number = '9876543210'
                profile.badge_number = 'KKRTC-P-4401'
                profile.is_authorized_pilot = True
                profile.save()
                self.stdout.write(f'Updated profile for {pilot_user.username}')
            else:
                self.stdout.write(self.style.SUCCESS(f'Created profile for {pilot_user.username} (Pilot: 9876543210)'))

            # 2. Bus: KA-34-A-1001 assigned to Anil
            bus, bus_created = Bus.objects.get_or_create(
                registration_number='KA-34-A-1001',
                defaults={
                    'pilot': pilot_user,
                    'is_active': True,
                }
            )
            if not bus_created:
                bus.pilot = pilot_user
                bus.is_active = True
                bus.save()
                self.stdout.write(f'Updated bus {bus.registration_number}')
            else:
                self.stdout.write(self.style.SUCCESS(f'Created bus {bus.registration_number}'))

            # 3. Routes
            # Route 1: Bengaluru to Ballari
            r1, r1_created = Route.objects.get_or_create(
                route_id='R001',
                defaults={
                    'source_name': 'Bengaluru',
                    'source_latitude': Decimal('12.971599'),
                    'source_longitude': Decimal('77.594563'),
                    'destination_name': 'Ballari',
                    'destination_latitude': Decimal('15.139393'),
                    'destination_longitude': Decimal('76.921448'),
                    'distance_km': Decimal('310.0'),
                    'is_active': True,
                }
            )
            if r1_created:
                self.stdout.write(self.style.SUCCESS(f'Created route {r1.route_id}: {r1}'))
            else:
                self.stdout.write(f'Route {r1.route_id} already exists')

            # Stops for R001
            stops_r1 = [
                ('Tumakuru', Decimal('13.340881'), Decimal('77.100616'), 1),
                ('Chitradurga', Decimal('14.225126'), Decimal('76.398003'), 2),
                ('Vijayanagara', Decimal('15.268936'), Decimal('76.390884'), 3),
            ]
            for name, lat, lon, seq in stops_r1:
                stop, s_created = Stop.objects.get_or_create(
                    route=r1,
                    sequence_order=seq,
                    defaults={
                        'stop_name': name,
                        'latitude': lat,
                        'longitude': lon,
                        'is_active': True,
                    }
                )
                if not s_created:
                    stop.stop_name = name
                    stop.latitude = lat
                    stop.longitude = lon
                    stop.is_active = True
                    stop.save()

            # Route 2: Ballari to Kampli
            r2, r2_created = Route.objects.get_or_create(
                route_id='R002',
                defaults={
                    'source_name': 'Ballari',
                    'source_latitude': Decimal('15.139393'),
                    'source_longitude': Decimal('76.921448'),
                    'destination_name': 'Kampli',
                    'destination_latitude': Decimal('15.405417'),
                    'destination_longitude': Decimal('76.602167'),
                    'distance_km': Decimal('45.0'),
                    'is_active': True,
                }
            )
            if r2_created:
                self.stdout.write(self.style.SUCCESS(f'Created route {r2.route_id}: {r2}'))
            else:
                self.stdout.write(f'Route {r2.route_id} already exists')

        self.stdout.write(self.style.SUCCESS('Successfully seeded KKRTC initial data!'))
