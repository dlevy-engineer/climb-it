from fastapi.testclient import TestClient
import pytest


def test_health_check():
    """Placeholder test - will be expanded when test DB is configured"""
    # TODO: Set up test database fixture
    assert True


def test_location_format():
    """Test the location hierarchy formatter"""
    from routers.crags import format_location

    # Test nested hierarchy
    hierarchy = {
        "name": "All Locations",
        "url": "https://mountainproject.com",
        "child": {
            "name": "California",
            "url": "https://mountainproject.com/area/california",
            "child": {
                "name": "Yosemite",
                "url": "https://mountainproject.com/area/yosemite",
                "child": None
            }
        }
    }
    assert format_location(hierarchy) == "All Locations > California > Yosemite"

    # Test empty hierarchy
    assert format_location(None) == "Unknown"
    assert format_location({}) == "Unknown"
