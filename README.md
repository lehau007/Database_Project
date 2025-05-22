
# Database_Project

This project is a web application built using Django to demonstrate the integration between web development and database management (PostgreSQL).

## 📁 Project Structure

```
Database_Project/
└── nearly_completed_demo_web/
    ├── mysite/         # Django project folder
    ├── manage.py       # Django management script
```

## 🛠️ Technologies Used

- **Backend**: Python (Django)
- **Frontend**: HTML, CSS, JavaScript
- **Database**: PostgreSQL (PLpgSQL)

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/lehau007/Database_Project.git
cd Database_Project/nearly_completed_demo_web
```

### 2. Install Dependencies

Make sure you have Python and PostgreSQL installed. Then install the required Python libraries:

```bash
pip install -r requirements.txt
```

> If `requirements.txt` is not available, install Django manually:
```bash
pip install django
```

### 3. Configure the Database

Open the folder `nearly_completed_demo_web` in **Visual Studio Code** (or any code editor). 

- Navigate to `mysite/settings.py`
- Find the `DATABASES` section and edit it to match your PostgreSQL setup:

```python
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'your_database_name',
        'USER': 'your_username',
        'PASSWORD': 'your_password',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}
```

### 4. Run the Web App Locally

After configuring the database and installing all required libraries, run these commands in the terminal:

```bash
python manage.py migrate
python manage.py runserver
```

Then open your browser and visit: [http://127.0.0.1:8000/](http://127.0.0.1:8000/)


### 5. Import the Database Schema

To set up the initial database schema using the provided `project_ver3.sql` file:

1. Open your terminal and log in to your PostgreSQL server:

```bash
psql -U your_username -d your_database_name
```

2. Once logged in, run the following command to import the schema:

```sql
\i path/to/database.sql
```

> Replace `path/to/project_ver3.sql` with the actual path to the `project_ver3.sql` file.

After this step, your database will be populated with the necessary tables and data.

