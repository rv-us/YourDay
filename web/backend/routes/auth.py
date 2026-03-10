from flask import Blueprint, jsonify, request
from firebase_admin import auth

auth_bp = Blueprint("auth", __name__)


@auth_bp.route("/api/auth/verify", methods=["POST"])
def verify_token():
    body = request.get_json() or {}
    id_token = body.get("idToken", "").strip()
    if not id_token:
        return jsonify({"error": "idToken is required"}), 400

    try:
        decoded = auth.verify_id_token(id_token)
        return jsonify({
            "uid": decoded["uid"],
            "email": decoded.get("email", ""),
            "displayName": decoded.get("name", ""),
        })
    except Exception as e:
        return jsonify({"error": "Invalid token", "detail": str(e)}), 401
