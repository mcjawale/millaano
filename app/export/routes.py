from flask import Blueprint
bp = Blueprint('export', __name__)
@bp.route('/')
def index(): return 'exp'
