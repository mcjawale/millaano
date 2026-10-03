from flask import Blueprint
bp = Blueprint('billing', __name__)
@bp.route('/')
def index(): return 'bill'
