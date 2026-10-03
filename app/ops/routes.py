from flask import Blueprint
bp = Blueprint('ops', __name__)
@bp.route('/')
def index(): return 'ops'
