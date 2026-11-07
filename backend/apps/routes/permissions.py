from rest_framework import permissions


class IsAdminOrReadOnly(permissions.BasePermission):
    """
    Custom permission allowing read access to authenticated users (passengers, pilots, admins),
    while restricting write operations (CREATE, UPDATE, DELETE) exclusively to administrators/staff.
    """

    def has_permission(self, request, view):
        # Read-only methods (GET, HEAD, OPTIONS) are permitted to authenticated users.
        if request.method in permissions.SAFE_METHODS:
            return bool(request.user and request.user.is_authenticated)

        # Write operations require staff or superuser status.
        return bool(
            request.user and
            request.user.is_authenticated and
            (request.user.is_staff or request.user.is_superuser)
        )
