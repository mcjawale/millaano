from flask import Blueprint, render_template, request, redirect, url_for, session, g, flash
from werkzeug.security import generate_password_hash, check_password_hash
from tenancy import require_auth

bp = Blueprint('auth', __name__)

def db():
    from app import get_db
    return get_db()

@bp.route('/auth/login', methods=['GET','POST'])
def login():
    if request.method == 'POST':
        un = request.form.get('username','').strip()
        pw = request.form.get('password','')
        cur = db().execute('''SELECT id,company_id,username,password_hash,full_name,role,is_active
                               FROM users WHERE username=? AND is_active=1''', (un,))
        u = cur.fetchone()
        if u and check_password_hash(u['password_hash'], pw):
            session['user_id'] = u['id']
            db().execute('UPDATE users SET last_login_at=datetime("now") WHERE id=?', (u['id'],))
            db().commit()
            cid, slug = u['company_id'], None
            if cid:
                c = db().execute('SELECT slug FROM companies WHERE id=?', (cid,))
                r = c.fetchone()
                slug = r['slug'] if r else None
            if slug:
                nxt = request.args.get('next') or url_for('dashboard.index', slug=slug)
                return redirect(nxt)
            flash('Account has no company', 'error')
        else:
            flash('Invalid username or password', 'error')
    return render_template('auth/login.html')

@bp.route('/auth/logout')
def logout():
    session.clear()
    return redirect(url_for('auth.login'))

@bp.route('/auth/signup', methods=['GET','POST'])
def signup():
    if request.method == 'POST':
        company = request.form.get('company','').strip()
        full_name = request.form.get('full_name','').strip() or company
        username = request.form.get('username','').strip()
        email = request.form.get('email','').strip()
        pw1 = request.form.get('password1','')
        pw2 = request.form.get('password2','')
        if not company or not username or not pw1 or pw1 != pw2:
            flash('All fields required and passwords must match', 'error')
            return render_template('auth/signup.html')
        from tenancy import slugify
        slug = slugify(company)
        # ensure unique slug
        base = slug
        i = 1
        while db().execute('SELECT id FROM companies WHERE slug=?', (slug,)).fetchone():
            slug = f'{base}-{i}'; i += 1
        db().execute('''INSERT INTO companies (name,slug,contact_email) VALUES (?,?,?)''', (company, slug, email or None))
        cid = db().execute('SELECT last_insert_rowid() as id').fetchone()['id']
        ph = generate_password_hash(pw1)
        db().execute('''INSERT INTO users (company_id,username,password_hash,full_name,email,role,is_active)
                        VALUES (?,?,?,?,?,'owner',1)''', (cid, username, ph, full_name, email or None))
        db().execute('UPDATE users SET last_login_at=datetime("now") WHERE id=last_insert_rowid()')
        db().commit()
        flash('Company created. Welcome!', 'ok')
        return redirect(url_for('auth.login'))
    return render_template('auth/signup.html')

@bp.route('/auth/profile')
@require_auth
def profile():
    return render_template('auth/profile.html', user=g.user)

@bp.route('/auth/company-select')
@require_auth
def company_select():
    c = db().execute('SELECT id,name,slug FROM companies WHERE id=?', (g.company_id,))
    r = c.fetchone()
    if r:
        return redirect(url_for('dashboard.index', slug=r['slug']))
    return redirect(url_for('auth.login'))
