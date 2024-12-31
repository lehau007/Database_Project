After install all lib.

To run this web in local host: 

  1. Setting database:
     Firstly, open folder "nearly completed demo web" in visual code such that link of terminal is this folder. After that, focus on folder "mysite", open settings.py
     In this file, find database and change this code to your database name, your user, your password.

  2. Run these command in terminal:
     python manage.py migrate
     python manage.py runserver
