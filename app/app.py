from flask import Flask, request, session, g, redirect, url_for
from werkzeug.security import generate_password_hash, check_password_hash
import sqlite3
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
INSTANCE_DIR = BASE_DIR / 'instance'
DB_PATH = INSTANCE_DIR / 'sahan_fleet.sqlite'

def create_app():
    app = Flask(__name__, static_folder='static', template_folder='templates')
    app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-key-change-later')

    INSTANCE_DIR.mkdir(exist_ok=True)

    def get_db():
        db = getattr(g, '_database', None)
        if db is None:
            db = g._database = sqlite3.connect(DB_PATH)
            db.row_factory = sqlite3.Row
            db.execute('PRAGMA foreign_keys=ON')
        return db

    @app.teardown_appcontext
    def close_db(e=None):
        db = getattr(g, '_database', None)
        if db is not None:
            db.close()

    def init_db():
        with app.app_context():
            schema = (BASE_DIR / 'schema.sql').read_text(encoding='utf-8')
            get_db().executescript(schema)
            get_db().commit()

    app.init_db = init_db
            from tenancy import resolve_from_url
            resolve_from_url()
        except Exception:
            pass

    # blueprints
    from .auth.routes import bp as auth_bp
    app.register_blueprint(auth_bp)

    from .dashboard.routes import bp as dash_bp
    app.register_blueprint(dash_bp)

    from .users.routes import bp as users_bp
    app.register_blueprint(users_bp)

    from .fleet.routes import bp as fleet_bp
    app.register_blueprint(fleet_bp)

    from .ops.routes import bp as ops_bp
    app.register_blueprint(ops_bp)

    from .records.routes import bp as rec_bp
    app.register_blueprint(rec_bp)

    from .export.routes import bp as exp_bp
    app.register_blueprint(exp_bp)

    from .billing.routes import bp as bill_bp
    app.register_blueprint(bill_bp)

    @app.route('/')
    def home():
        if g.user:
            if g.company and g.company.get('slug'):
                return redirect(url_for('dashboard.index', slug=g.company['slug']))
            return redirect(url_for('auth.company_select'))
        return redirect(url_for('auth.login'))

    return app

app = create_app()

if __name__ == '__main__':
    app = create_app()
    # init if first run
    if not DB_PATH.exists():
        from app import app as aapp
        with aapp.app_context():
            aapp.init_db()
    app.run(debug=True, port=5000)