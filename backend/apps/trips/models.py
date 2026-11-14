from django.conf import settings
from django.db import models
from django.db.models import Q

from apps.buses.models import Bus
from apps.routes.models import Route


class Trip(models.Model):
    class Status(models.TextChoices):
        ACTIVE = 'ACTIVE', 'Active'
        COMPLETED = 'COMPLETED', 'Completed'

    pilot = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='trips',
    )
    bus = models.ForeignKey(Bus, on_delete=models.PROTECT, related_name='trips')
    route = models.ForeignKey(
        Route,
        on_delete=models.PROTECT,
        related_name='trips',
    )
    status = models.CharField(
        max_length=12,
        choices=Status.choices,
        default=Status.ACTIVE,
    )
    start_time = models.DateTimeField(auto_now_add=True)
    end_time = models.DateTimeField(null=True, blank=True)
    current_latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        help_text='Latest recorded latitude (-90.0 to +90.0)',
    )
    current_longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        help_text='Latest recorded longitude (-180.0 to +180.0)',
    )
    current_speed = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        null=True,
        blank=True,
        help_text='Latest vehicle speed in km/h',
    )
    current_bearing = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        null=True,
        blank=True,
        help_text='Compass bearing/heading in degrees (0-360)',
    )
    last_gps_update = models.DateTimeField(
        null=True,
        blank=True,
        help_text='Timestamp of the latest received GPS update',
    )

    class Meta:
        ordering = ('-start_time',)
        constraints = [
            models.UniqueConstraint(
                fields=('pilot',),
                condition=Q(status='ACTIVE'),
                name='one_active_trip_per_pilot',
            ),
        ]

    def __str__(self):
        return f'{self.route} ({self.status})'
