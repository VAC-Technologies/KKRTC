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
        if self.destination_name:
            self.destination_name = self.destination_name.strip()

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
        validators=LATITUDE_VALIDATORS,
        verbose_name='Latitude',
        help_text='Geographical latitude (-90.0 to +90.0)',
    )
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
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
        validate_geographical_coordinates(self.latitude, self.longitude)
        if self.sequence_order is not None and self.sequence_order < 1:
            raise ValidationError({'sequence_order': 'Sequence order must be 1 or greater.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.stop_name} (#{self.sequence_order})'
