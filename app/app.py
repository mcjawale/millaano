from flask import Flask, request, session, g, redirect, url_for
from werkzeug.security import generate_password_hash, check_password_hash
import sqlite3
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
INSTANCE_DIR = BASE_DIR / 'instance'
DB_PATH = INSTANCE_DIR / 'sahan_fleet.sqlite'

def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DB_PATH)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
    return db

def init_db(app):
    with app.app_context():
        schema = (BASE_DIR / 'schema.sql').read_text(encoding='utf-8')
        get_db().executescript(schema)
        get_db().commit()

def create_app():
    app = Flask(__name__, static_folder='static', template_folder='templates')
    app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-key-change-later')

    INSTANCE_DIR.mkdir(exist_ok=True)

    @app.teardown_appcontext
    def close_db(e=None):
        db = getattr(g, '_database', None)
        if db is not None:
            db.close()

    @app.before_request
    def load_user():
        g.user = None
        g.company = None
        g.company_id = None
        uid = session.get('user_id')
        if uid:
            cur = get_db().execute('''SELECT id,company_id,username,full_name,role,is_active,email
                                      FROM users WHERE id=? AND is_active=1''', (uid,))
            u = cur.fetchone()
            if u:
                g.user = dict(u)
                g.user_id = u['id']
                g.company_id = u['company_id']
                c = get_db().execute('SELECT id,name,slug,is_active FROM companies WHERE id=?', (g.company_id,))
                cr = c.fetchone()
                if cr and cr['is_active'] == 1:
                    g.company = dict(cr)
        try:
            from tenancy import resolve_from_url
            resolve_from_url()
        except Exception:
            pass

    from .auth.routes import bp as auth_bp
    from .dashboard.routes import bp as dash_bp
    from .users.routes import bp as users_bp
    from .fleet.routes import bp as fleet_bp
    from .ops.routes import bp as ops_bp
    from .records.routes import bp as rec_bp
    from .export.routes import bp as exp_bp
    from .billing.routes import bp as bill_bp
    app.register_blueprint(auth_bp)
    app.register_blueprint(dash_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(fleet_bp)
    app.register_blueprint(ops_bp)
    app.register_blueprint(rec_bp)
    app.register_blueprint(exp_bp)
    app.register_blueprint(bill_bp)

    @app.route('/')
    def home():
        if g.user:
            if g.company and g.company.get('slug'):
                return redirect(url_for('dashboard.index', slug=g.company['slug']))
            return redirect(url_for('auth.company_select'))
        return redirect(url_for('auth.login'))

    app.init_db = lambda: init_db(app)
    return app
