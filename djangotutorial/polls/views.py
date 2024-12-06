from django.shortcuts import render

from .models import Choice, Question

from django.http import HttpResponse, HttpResponseRedirect
from django.template import loader
from django.urls import reverse

from django.db import connection
from django.shortcuts import render

from django.http import Http404
from django.shortcuts import get_object_or_404
from django.db.models import F


from django.shortcuts import redirect
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth import login
from django.contrib import messages

from django.db import IntegrityError

from django.shortcuts import render, redirect
from django.contrib import messages
from django.db import connection

def index(request):
    latest_question_list = Question.objects.order_by("-pub_date")[:5]
    template = loader.get_template("polls/index.html")
    context = {
        "latest_question_list": latest_question_list,
    }
    return HttpResponse(template.render(context, request))

def signup_view(request):
    if request.method == 'POST':
        first_name = request.POST.get('first_name')
        last_name = request.POST.get('last_name')
        username = request.POST.get('username')
        password = request.POST.get('password')

        # Validate input fields
        if not (first_name and last_name and username and password):
            messages.error(request, "All fields are required.")
            return render(request, 'polls/signup.html')

        # Check exitance
        with connection.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) FROM student WHERE username = %s", [username])
            result = cursor.fetchone()

        if result[0] > 0:
            messages.error(request, "Username already exists. Please choose a different one.")
            return render(request, 'polls/signup.html')

        # Insert student
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO student (first_name, last_name, username, password)
                VALUES (%s, %s, %s, %s)
            """, [first_name, last_name, username, password])

        # Redirect to the login page with a success message
        return redirect('/polls/signup_success/')

    return render(request, 'polls/signup.html')

def signup_success(request):
    return render(request, 'polls/signup_success.html')  # Updated path

def profile(request):
    return render(request, 'polls/profile.html')  # Updated path

def home(request):
    return render(request, 'polls/index.html')  # Home page

def login_view(request):
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        
        # Custom database query to validate user
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT student_id FROM student WHERE username = %s AND password = %s",
                [username, password]
            )
            user = cursor.fetchone()
        
        if user:
            # Successful login: Redirect to profile page
            return HttpResponseRedirect('/polls/profile/')
        else:
            # Failed login: Render login page with error message
            return render(request, 'login.html', {
                'error': 'Invalid username or password.'
            })

    # For GET requests, render the login page
    return render(request, 'login.html')
