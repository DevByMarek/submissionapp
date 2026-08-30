from flask import Flask, render_template, request, redirect, url_for, flash, send_from_directory, abort, render_template_string, session
from werkzeug.exceptions import RequestEntityTooLarge
from werkzeug.utils import secure_filename
import os
import datetime
from unidecode import unidecode
from dotenv import load_dotenv
from flask_wtf import CSRFProtect
from flask_limiter import Limiter
import uuid
from werkzeug.middleware.proxy_fix import ProxyFix

#CONTANTS
ALLOWED_EXTENSION = (".zip", ".rar",".pkt",".pka", ".cpp", ".py", ".jpeg", ".jpg", ".png", ".heic", ".doc", ".docx", ".rtf", ".txt", ".xlsx", ".xls", ".pdf", ".ppt", ".pptx", ".ipynb")
MAX_CONTENT_LENGHT = 50 # In Megabytes

#FLASK CONFIG
load_dotenv()  # load .env from current directory
app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_CONTENT_LENGHT * 1024 * 1024  # CONVERT TO MBS
app.config["SECRET_KEY"] = os.getenv("MY_SECRET_KEY")
csrf = CSRFProtect(app)
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)
app.config.update(
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=True
)

@app.before_request
def ensure_session_id():
    if "rl_id" not in session:
        session["rl_id"] = str(uuid.uuid4())

def rate_limit_key():
    return session.get("rl_id", "no-session")


limiter = Limiter(
    key_func=rate_limit_key,
    app=app,
    storage_uri="redis://localhost:6379/0"
)


#MAIN WEBSITE - INDEX.html
@app.route("/")
def index():
    return render_template("index.html")

#HOMEWORK SUBMISSION WEBSITE - HOMEWORK.html
@app.route("/homework")
def homework():
    return render_template("homework.html")

#CLOUD DOWNLOADING WEBSITE - CLOUD.html
@app.route("/cloud")
def cloud():
    DOWNLOAD_FOLDER = rf"/var/application_data/submission_app/cloud/teacher"
    DOWN_FOLDER_EXIST = os.path.exists(DOWNLOAD_FOLDER)

    file_array = []
    if DOWN_FOLDER_EXIST:
        for i in os.listdir(DOWNLOAD_FOLDER):
            file_array.append(i)

    #RENDER WEBSITE - IF UPFOLDER WITH TODAY DAY EXISTS VIEW SUBMISSION ELSE NO
    return render_template("cloud.html", is_true=True, download_file=file_array)


#EXERCISES SUBMISSION AND DOWNLOAD WEBSITE ACCORDING TO DATE AND DATEFOLDER exercise.html
@app.route("/exercise")
def exercise():

    #GET ACTUAL TIME AFTER ALL CALL ROUTE - VIEWS ONLY FOLDER WITH TODAY DATUM
    date = f"{datetime.date.today().day}.{datetime.date.today().month}.{datetime.date.today().year}"

    #PATH TO FOLDERS
    UPLOAD_FOLDER = rf"/var/application_data/submission_app/exercise/{date}"
    DOWNLOAD_FOLDER = rf"/var/application_data/submission_app/exercise/resources"

    #TEST EXISTS FOLDER
    UP_FOLDER_EXIST = os.path.exists(UPLOAD_FOLDER)
    DOWN_FOLDER_EXIST = os.path.exists(DOWNLOAD_FOLDER)

    #VIEW FILE TO DOWNLOAD FROM FILESYSTEM
    file_array = []
    if DOWN_FOLDER_EXIST:
        for i in os.listdir(DOWNLOAD_FOLDER):
            file_array.append(i)

    #RENDER WEBSITE - IF UPFOLDER WITH TODAY DAY EXISTS VIEW SUBMISSION ELSE NO
    return render_template("exercise.html", is_true=UP_FOLDER_EXIST, download_file=file_array)

#EXERCISES SUBMISSION FILE API - FILE TO FILESYSTEM - FILEBROWSER SW AS FRONTEND
@app.route("/saveform", methods=["POST"] )
@limiter.limit("5 per hour")
def save_data():

    #GET TODAY DATE FOR SELECT CORRECT FOLDER IN FILEdSYSTEM
    date = f"{datetime.date.today().day}.{datetime.date.today().month}.{datetime.date.today().year}"

    #UPLOAD FOLDER PATH
    UPLOAD_FOLDER = rf"/var/application_data/submission_app/exercise/{date}"

    #RAW HTML FORM DATA TO PYTHON VARIABLES
    receive_file = request.files.get("file")
    form_fname = unidecode(request.form.get("fname")).capitalize()
    form_lname = unidecode(request.form.get("lname")).capitalize()
    form_group = unidecode(request.form.get("group")).capitalize()
    temp_class = request.form.get("class")
    receive_filename = secure_filename(unidecode(receive_file.filename))

    #PROCESSING INPUT VARIABLES
    form_class = f"{temp_class[0]}.{temp_class[1]}"
    _ , ext = os.path.splitext(receive_filename)
    ext = ext.lower()
    save_filename = f"{form_lname}{form_fname}{form_group}{ext}"

    #LOGIC FOR PERMIT ONLY ALLOWED EXTENSIONS
    if ext not in ALLOWED_EXTENSION:
        flash(f"Odoslanie zlyhalo - nepodporovaná prípona -> {ext}", "error")
        return redirect(url_for("exercise"))
    
    #IF DATEFOLDER NOT CONTAIN CLASS FOLDER, CREATE IT
    os.makedirs(rf"{UPLOAD_FOLDER}/{form_class}", exist_ok=True)

    #TEST FILENAME WHETHER EXIST - IF EXIST - ADD VERSION FILE NUMBER TO FILENAME 
    base_name, ext = os.path.splitext(save_filename)
    counter = 1
    count_test = 0
    while os.path.exists(rf"{UPLOAD_FOLDER}/{form_class}/{save_filename}"):
        count_test = counter
        save_filename = f"{base_name}_{counter}{ext}"
        counter += 1
        base_name, ext = os.path.splitext(save_filename)
    if count_test > 0:
        flash(f"Duplicita uložená pod číslom -> {count_test}", "info")


    #SAVE FILE TO FILESYSTEM
    receive_file.save(rf"{UPLOAD_FOLDER}/{form_class}/{save_filename}")

    #SUCCES FLASH MESSAGE AND REDIRECT TO EXERCISES PAGE
    flash("Úspešne odoslané", "succefull")
    return redirect(url_for("exercise"))

#HOMEWORK SUBMISSION FILE API - FILE TO FILESYSTEM - FILEBROWSER SW AS FRONTEND
@app.route("/savehomework", methods=["POST"] )
@limiter.limit("5 per hour")
def save_homework():

    #UPLOAD FOLDER PATH
    UPLOAD_FOLDER = rf"/var/application_data/submission_app/homework"

    #RAW HTML FORM DATA TO PYTHON VARIABLES
    receive_file = request.files.get("file")
    form_fname = unidecode(request.form.get("fname")).capitalize()
    form_lname = unidecode(request.form.get("lname")).capitalize()
    selected_class = request.form.get("class")
    selected_folder = request.form.get("folder")
    receive_filename = secure_filename(unidecode(receive_file.filename))

    #PROCESSING INPUT VARIABLES
    processed_class = f"{selected_class[0]}.{selected_class[1]}"
    _ , ext = os.path.splitext(receive_filename)
    ext = ext.lower()
    save_filename = f"{form_lname}{form_fname}{ext}"

    #LOGIC FOR PERMIT ONLY ALLOWED EXTENSIONS
    if ext not in ALLOWED_EXTENSION:
        flash(f"Odoslanie zlyhalo - nepodporovaná prípona -> {ext}", "error")
        return redirect(url_for("index"))
    
    #IF DATEFOLDER NOT CONTAIN CLASS FOLDER, CREATE IT
    os.makedirs(rf"{UPLOAD_FOLDER}/{processed_class}", exist_ok=True)

    #TEST FILENAME WHETHER EXIST - IF EXIST - ADD VERSION FILE NUMBER TO FILENAME 
    base_name, ext = os.path.splitext(save_filename)
    counter = 1
    count_test = 0
    while os.path.exists(rf"{UPLOAD_FOLDER}/{processed_class}/{selected_folder}/{save_filename}"):
        count_test = counter
        save_filename = f"{base_name}_{counter}{ext}"
        counter += 1
        base_name, ext = os.path.splitext(save_filename)
    if count_test > 0:
        flash(f"Duplicita uložená pod číslom -> {count_test}", "info")

    #SAVE FILE TO FILESYSTEM
    receive_file.save(rf"{UPLOAD_FOLDER}/{processed_class}/{selected_folder}/{save_filename}")

    #SUCCES FLASH MESSAGE AND REDIRECT TO EXERCISES PAGE
    flash("Úspešne odoslané", "succefull")
    return redirect(url_for("homework"))

@app.route("/exercise/download/<path:filename>")
def download(filename):
    DOWNLOAD_FOLDER = rf"/var/application_data/submission_app/exercise/resources"
    try:
        return send_from_directory(
            DOWNLOAD_FOLDER,
            filename,
            as_attachment=True
        )
    except FileNotFoundError:
        abort(404)

@app.errorhandler(RequestEntityTooLarge)
def too_large(e):
    flash(f"Súbor je príliš veľký. Maximálna veľkosť je {MAX_CONTENT_LENGHT} MB.", "error")
    return redirect("/")

@app.route("/load-folders")
def load_folders():
    selected_class = request.args.get("class")
    selected_class = f"{selected_class[0]}.{selected_class[1]}"

    if not selected_class:
        return "<option value=''>Žiadna trieda</option>"

    path = os.path.join(rf"/var/application_data/submission_app/homework/{selected_class}")

    if not os.path.isdir(path):
        return "<option value=''>Žiadne priečinky</option>"

    folders = [
        f for f in os.listdir(path)
        if os.path.isdir(os.path.join(path, f))
    ]

    return render_template_string("""
        <option value="">Vyber priečinok</option>
        {% for folder in folders %}
            <option value="{{ folder }}">{{ folder }}</option>
        {% endfor %}
    """, folders=folders)


@app.route("/cloud/<path:filename>")
def cloud_download(filename):
    DOWNLOAD_FOLDER_CLOUD = rf"/var/application_data/submission_app/cloud/teacher"
    try:
        return send_from_directory(
            DOWNLOAD_FOLDER_CLOUD,
            filename,
            as_attachment=True
        )
    except FileNotFoundError:
        abort(404)

@app.errorhandler(429)
def too_many_requests(e):
    flash("Príliš veľa pokus -> Max. 5 za hodinu", "error")
    return redirect(url_for("exercise"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
