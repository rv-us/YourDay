from flask import Blueprint, jsonify, request
from firebase_admin import firestore
from auth_middleware import require_auth
from models.serializers import serialize_value

garden_bp = Blueprint("garden", __name__)
db = None


def get_db():
    global db
    if db is None:
        db = firestore.client()
    return db


def extract_garden_fields(data):
    return {
        "placedPlants": serialize_value(data.get("placedPlants", [])),
        "unplacedPlantsInventory": data.get("unplacedPlantsInventory", {}),
        "numberOfOwnedPlots": data.get("numberOfOwnedPlots", 2),
        "gardenValue": data.get("gardenValue", 0.0),
        "fertilizerCount": data.get("fertilizerCount", 0),
    }


@garden_bp.route("/api/garden", methods=["GET"])
@require_auth
def get_garden():
    uid = request.uid
    doc = get_db().collection("users").document(uid).collection("playerData").document("playerStats").get()

    if not doc.exists:
        return jsonify({"error": "Player stats not found"}), 404

    return jsonify(extract_garden_fields(doc.to_dict() or {}))


@garden_bp.route("/api/garden/friend/<friend_id>", methods=["GET"])
@require_auth
def get_friend_garden(friend_id):
    uid = request.uid

    # Verify friendship
    friend_doc = get_db().collection("users").document(uid).collection("friends").document(friend_id).get()
    if not friend_doc.exists or (friend_doc.to_dict() or {}).get("status") != "accepted":
        return jsonify({"error": "Not friends with this user"}), 403

    doc = get_db().collection("users").document(friend_id).collection("playerData").document("playerStats").get()
    if not doc.exists:
        return jsonify({"error": "Friend's stats not found"}), 404

    garden_data = extract_garden_fields(doc.to_dict() or {})
    garden_data["friendId"] = friend_id
    garden_data["displayName"] = (friend_doc.to_dict() or {}).get("displayName", "")
    return jsonify(garden_data)
