from decimal import Decimal
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone


LATITUDE_VALIDATORS = [
    MinValueValidator(Decimal('-90.0'), message='Latitude must be between -90.0 and 90.0 degrees.'),
    MaxValueValidator(Decimal('90.0'), message='Latitude must be between -90.0 and 90.0 degrees.'),
]

LONGITUDE_VALIDATORS = [
    MinValueValidator(Decimal('-180.0'), message='Longitude must be between -180.0 and 180.0 degrees.'),
    MaxValueValidator(Decimal('180.0'), message='Longitude must be between -180.0 and 180.0 degrees.'),
]

KARNATAKA_LOCATION_COORDINATES = {
    'bengaluru': (Decimal('12.971599'), Decimal('77.594563')),
    'bangalore': (Decimal('12.971599'), Decimal('77.594563')),
    'ballari': (Decimal('15.139393'), Decimal('76.921448')),
    'bellary': (Decimal('15.139393'), Decimal('76.921448')),
    'tumakuru': (Decimal('13.340881'), Decimal('77.100616')),
    'tumkur': (Decimal('13.340881'), Decimal('77.100616')),
    'chitradurga': (Decimal('14.225126'), Decimal('76.398003')),
    'vijayanagara': (Decimal('15.268936'), Decimal('76.390884')),
    'hosapete': (Decimal('15.268936'), Decimal('76.390884')),
    'hospet': (Decimal('15.268936'), Decimal('76.390884')),
    'kampli': (Decimal('15.405417'), Decimal('76.602167')),
    'hubballi': (Decimal('15.364708'), Decimal('75.123955')),
    'hubli': (Decimal('15.364708'), Decimal('75.123955')),
    'dharwad': (Decimal('15.458947'), Decimal('75.007812')),
    'kalaburagi': (Decimal('17.329731'), Decimal('76.834297')),
    'gulbarga': (Decimal('17.329731'), Decimal('76.834297')),
    'raichur': (Decimal('16.207600'), Decimal('77.346300')),
    'koppal': (Decimal('15.352400'), Decimal('76.155700')),
    'bidar': (Decimal('17.910400'), Decimal('77.519900')),
    'yadgir': (Decimal('16.762800'), Decimal('77.137800')),
    'belagavi': (Decimal('15.849700'), Decimal('74.497700')),
    'belgaum': (Decimal('15.849700'), Decimal('74.497700')),
    'davanagere': (Decimal('14.464400'), Decimal('75.921800')),
    'shivamogga': (Decimal('13.929900'), Decimal('75.568100')),
    'mangaluru': (Decimal('12.914100'), Decimal('74.856000')),
    'mysuru': (Decimal('12.295800'), Decimal('76.639400')),
    'mysore': (Decimal('12.295800'), Decimal('76.639400')),
    'hostel': (Decimal('13.035500'), Decimal('77.596500')),
    't -shop': (Decimal('13.035500'), Decimal('77.596500')),
    'vinayak temple': (Decimal('13.045500'), Decimal('77.606500')),
}


def resolve_karnataka_coordinates(name):
    """
    Resolves known Karnataka transit locations and bus stands to latitude and longitude.
    Provides internal coordinate defaults if none are provided by the user.
    """
    if not name:
        return (Decimal('14.520400'), Decimal('75.722400'))
    clean = str(name).strip().lower()
    for key, coords in KARNATAKA_LOCATION_COORDINATES.items():
        if key in clean or clean in key:
            return coords
    # Default to geographic center of Karnataka
    return (Decimal('14.520400'), Decimal('75.722400'))


def validate_geographical_coordinates(latitude, longitude):
    """
    Validates that latitude is in [-90, 90] and longitude is in [-180, 180].
    Raises ValidationError if either is out of range.
    """
    if latitude is not None:
        try:
            lat = Decimal(str(latitude))
            if lat < Decimal('-90.0') or lat > Decimal('90.0'):
                raise ValidationError('Latitude must be between -90.0 and 90.0 degrees.')
        except (ValueError, TypeError):
            raise ValidationError('Invalid latitude value.')

    if longitude is not None:
        try:
            lon = Decimal(str(longitude))
            if lon < Decimal('-180.0') or lon > Decimal('180.0'):
                raise ValidationError('Longitude must be between -180.0 and 180.0 degrees.')
        except (ValueError, TypeError):
            raise ValidationError('Invalid longitude value.')


class Route(models.Model):
    """
    Represents an official KKRTC bus route connecting an origin (From)
    to a destination (To), with optional distance and active status.
    """
    route_id = models.CharField(
        max_length=32,
        unique=True,
        db_index=True,
        default='',
        verbose_name='Route ID',
        help_text='Unique Route Identifier (e.g., R001, KK-01)',
    )
    source_name = models.CharField(
        max_length=120,
        verbose_name='From (Origin)',
        help_text='Starting origin location name',
    )
    source_latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        validators=LATITUDE_VALIDATORS,
        verbose_name='From Latitude',
        help_text='Origin latitude (-90.0 to +90.0)',
    )
    source_longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        validators=LONGITUDE_VALIDATORS,
        verbose_name='From Longitude',
        help_text='Origin longitude (-180.0 to +180.0)',
    )
    destination_name = models.CharField(
        max_length=120,
        verbose_name='To (Destination)',
        help_text='Destination location name',
    )
    destination_latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        validators=LATITUDE_VALIDATORS,
        verbose_name='To Latitude',
        help_text='Destination latitude (-90.0 to +90.0)',
    )
    destination_longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        validators=LONGITUDE_VALIDATORS,
        verbose_name='To Longitude',
        help_text='Destination longitude (-180.0 to +180.0)',
    )
    distance_km = models.DecimalField(
        max_digits=7,
        decimal_places=2,
        null=True,
        blank=True,
        default=Decimal('0.0'),
        validators=[MinValueValidator(Decimal('0.0'))],
        verbose_name='Distance (km)',
        help_text='Approximate distance in kilometers',
    )
    is_active = models.BooleanField(
        default=True,
        verbose_name='Is Active',
        help_text='Designates whether this route is operational',
    )
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('route_id', 'source_name', 'destination_name')
        verbose_name = 'Route'
        verbose_name_plural = 'Routes'

    def clean(self):
        super().clean()
        if self.route_id:
            self.route_id = self.route_id.strip()
        if self.source_name:
            self.source_name = self.source_name.strip()
            if self.source_latitude is None or self.source_longitude is None:
                r_lat, r_lon = resolve_karnataka_coordinates(self.source_name)
                self.source_latitude = self.source_latitude or r_lat
                self.source_longitude = self.source_longitude or r_lon
        if self.destination_name:
            self.destination_name = self.destination_name.strip()
            if self.destination_latitude is None or self.destination_longitude is None:
                r_lat, r_lon = resolve_karnataka_coordinates(self.destination_name)
                self.destination_latitude = self.destination_latitude or r_lat
                self.destination_longitude = self.destination_longitude or r_lon

        validate_geographical_coordinates(self.source_latitude, self.source_longitude)
        validate_geographical_coordinates(self.destination_latitude, self.destination_longitude)

    def save(self, *args, **kwargs):
        # Auto-assign a unique route_id if omitted (supports tests or legacy calls)
        if not self.route_id:
            src = (self.source_name or 'SRC')[:3].upper()
            dst = (self.destination_name or 'DST')[:3].upper()
            base_code = f'{src}-{dst}'
            count = Route.objects.filter(route_id__startswith=base_code).count()
            self.route_id = f'{base_code}-{count + 1:02d}'
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.source_name} - {self.destination_name}'

    @property
    def display_name(self):
        return f'[{self.route_id}] {self.source_name} → {self.destination_name}'

    @property
    def stops_count(self):
        return self.stops.count()


class Stop(models.Model):
    """
    Represents an intermediate Via stop along a route, with coordinates
    and sequence order.
    """
    route = models.ForeignKey(
        Route,
        on_delete=models.CASCADE,
        related_name='stops',
        verbose_name='Route',
    )
    stop_name = models.CharField(
        max_length=120,
        verbose_name='Stop Name',
        help_text='Name of intermediate or transit stop',
    )
    latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        validators=LATITUDE_VALIDATORS,
        verbose_name='Latitude',
        help_text='Geographical latitude (-90.0 to +90.0)',
    )
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        validators=LONGITUDE_VALIDATORS,
        verbose_name='Longitude',
        help_text='Geographical longitude (-180.0 to +180.0)',
    )
    sequence_order = models.PositiveIntegerField(
        default=1,
        verbose_name='Sequence Order',
        help_text='Stop travel order along the route (1, 2, 3...)',
    )
    is_active = models.BooleanField(
        default=True,
        verbose_name='Is Active',
    )
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('sequence_order', 'id')
        verbose_name = 'Via Stop'
        verbose_name_plural = 'Via Stops'
        constraints = [
            models.UniqueConstraint(
                fields=('route', 'sequence_order'),
                name='unique_stop_sequence_per_route',
                deferrable=models.Deferrable.DEFERRED,
            ),
        ]

    def clean(self):
        super().clean()
        if self.stop_name:
            self.stop_name = self.stop_name.strip()
            if self.latitude is None or self.longitude is None:
                r_lat, r_lon = resolve_karnataka_coordinates(self.stop_name)
                self.latitude = self.latitude or r_lat
                self.longitude = self.longitude or r_lon
        validate_geographical_coordinates(self.latitude, self.longitude)
        if self.sequence_order is not None and self.sequence_order < 1:
            raise ValidationError({'sequence_order': 'Sequence order must be 1 or greater.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.stop_name} (#{self.sequence_order})'
