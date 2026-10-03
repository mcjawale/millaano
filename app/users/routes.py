from flask import Blueprint, render_template, request, redirect, url_for, g, flash
from werkzeug.security import generate_password_hash
from tenancy import require_auth, require_company_admin, slugify

bp = Blueprint('users', __name__, url_prefix='/app/<slug>/users')

@bp.url_value_preprocessor
def p(endpoint, values):
    from tenancy import resolve_from_url
    resolve_from_url()

@bp.before_request
def ensure_auth():
    if not g.user:
        from flask import redirect, request
        return redirect(url_for('auth.login', next=request.url))

@bp.route('/')
@require_company_admin
def list():
    db = __import__('app').get_db()
    rows = db.execute('''SELECT id,username,full_name,email,role,is_active,created_at FROM users
                         WHERE company_id=? ORDER BY id''', (g.company_id,)).fetchall()
    return render_template('users/list.html', rows=rows)

@bp.route('/new', methods=['GET','POST'])
@require_company_admin
def new():
    db = __import__('app').get_db()
    if request.method == 'POST':
        un = request.form.get('username','').strip()
        fn = request.form.get('full_name','').strip()
        em = request.form.get('email','').strip()
        role = request.form.get('role','staff')
        pw1 = request.form.get('password1','')
        pw2 = request.form.get('password2','')
        if not un or not pw1 or pw1 != pw2 or role not in ('owner','admin','staff','viewer'):
            flash('Invalid input', 'error')
            return render_template('users/new.html')
        ph = generate_password_hash(pw1)
        try:
            db.execute('''INSERT INTO users (company_id,username,password_hash,full_name,email,role,is_active)
                          VALUES (?,?,?,?,?,?,1)''', (g.company_id, un, ph, fn, em, role))
            db.commit()
            flash('User added', 'ok')
            return redirect(url_for('users.list', slug=g.company['slug']))
        except Exception as e:
            flash('Username may already exist', 'error')
    return render_template('users/new.html')
