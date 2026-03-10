"""Helpers to convert Firestore documents to JSON-serializable dicts."""
from datetime import datetime


def serialize_value(value):
    """Recursively serialize a Firestore value to a JSON-safe type."""
    if isinstance(value, datetime) or hasattr(value, "isoformat"):
        return value.isoformat()
    if isinstance(value, dict):
        return {k: serialize_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [serialize_value(item) for item in value]
    return value


def serialize_doc(doc):
    """Convert a Firestore DocumentSnapshot to a dict, adding 'id' from doc.id."""
    data = doc.to_dict() or {}
    result = {k: serialize_value(v) for k, v in data.items()}
    result["id"] = doc.id
    return result


def serialize_leaderboard_entry(doc, rank=None):
    """Serialize a leaderboard_entries document.

    Swift CodingKeys maps 'id' -> Firestore field 'userID'.
    So the stored field is 'userID', but doc.id is the Firebase UID.
    """
    data = doc.to_dict() or {}
    return {
        "id": doc.id,
        "userID": data.get("userID", doc.id),
        "displayName": data.get("displayName", ""),
        "playerLevel": data.get("playerLevel", 1),
        "gardenValue": data.get("gardenValue", 0.0),
        "rank": rank,
    }


def serialize_player_stats(doc):
    """Serialize the playerStats document with proper nested handling."""
    data = doc.to_dict() or {}
    result = {}

    for key, value in data.items():
        result[key] = serialize_value(value)

    result["id"] = doc.id
    return result
