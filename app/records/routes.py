from flask import Blueprint
bp = Blueprint('records', __name__)
@bp.route('/')
def index(): return 'rec'
