from flask import Blueprint
bp = Blueprint('fleet', __name__)
@bp.route('/')
def index(): return 'fleet'
