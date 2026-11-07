from django.contrib import admin, messages
from django.utils.html import format_html

from apps.routes.models import Route, Stop


class StopInline(admin.TabularInline):
    """
    Inline admin for managing intermediate Via stops directly within
    the Route edit/create page.
    """
    model = Stop
    extra = 1
    fields = ('sequence_order', 'stop_name', 'latitude', 'longitude', 'is_active')
    ordering = ('sequence_order',)
    show_change_link = True
    verbose_name = 'Via Stop'
    verbose_name_plural = 'Via Stops (Travel Sequence)'


@admin.register(Route)
class RouteAdmin(admin.ModelAdmin):
    """
    Administration interface for KKRTC Routes with inline Via stop management.
    """
    inlines = (StopInline,)
    list_display = (
        'route_id',
        'source_name',
        'destination_name',
        'stops_count_display',
        'distance_km',
        'is_active',
        'created_at',
    )
    list_filter = ('is_active', 'created_at')
    search_fields = ('route_id', 'source_name', 'destination_name')
    ordering = ('route_id',)
    save_on_top = True

    fieldsets = (
        ('Route Identification', {
            'fields': ('route_id', 'is_active'),
            'description': 'Unique route identification and operational status.',
        }),
        ('From (Starting Location)', {
            'fields': ('source_name', ('source_latitude', 'source_longitude')),
            'description': 'Origin terminal or starting stop with optional coordinates.',
        }),
        ('To (Destination)', {
            'fields': ('destination_name', ('destination_latitude', 'destination_longitude')),
            'description': 'Destination terminal with optional coordinates.',
        }),
        ('Route Details', {
            'fields': ('distance_km',),
            'classes': ('collapse',),
        }),
    )

    @admin.display(description='Via Stops')
    def stops_count_display(self, obj):
        count = obj.stops.count()
        if count == 0:
            return format_html('<span style="color: #888;">Direct (0 stops)</span>')
        return format_html('<strong>{}</strong> via stops', count)

    def delete_model(self, request, obj):
        """
        Safeguard against deleting routes currently utilized by active trips.
        """
        if hasattr(obj, 'trips') and obj.trips.filter(status='ACTIVE').exists():
            self.message_user(
                request,
                f'Cannot delete route "{obj.route_id}" because active trips are currently running on it.',
                level=messages.ERROR,
            )
            return
        super().delete_model(request, obj)

    def delete_queryset(self, request, queryset):
        """
        Safeguard against batch deletion of routes with active trips.
        """
        active_routes = queryset.filter(trips__status='ACTIVE').distinct()
        if active_routes.exists():
            active_ids = ', '.join(r.route_id for r in active_routes)
            self.message_user(
                request,
                f'Cannot delete the following route(s) with active trips: {active_ids}. Deletion aborted.',
                level=messages.ERROR,
            )
            return
        super().delete_queryset(request, queryset)


@admin.register(Stop)
class StopAdmin(admin.ModelAdmin):
    """
    Stand-alone administration interface for Via stops search and inspection.
    """
    list_display = (
        'route',
        'sequence_order',
        'stop_name',
        'latitude',
        'longitude',
        'is_active',
        'created_at',
    )
    list_filter = ('is_active', 'route')
    search_fields = (
        'stop_name',
        'route__route_id',
        'route__source_name',
        'route__destination_name',
    )
    ordering = ('route', 'sequence_order')
