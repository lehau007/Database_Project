from django.shortcuts import render

from .models import Choice, Question

from django.http import HttpResponse, HttpResponseRedirect
from django.template import loader
from django.urls import reverse

from django.http import Http404
from django.shortcuts import get_object_or_404
from django.db.models import F


from django.shortcuts import redirect
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth import login
from django.contrib import messages


def index(request):
    latest_question_list = Question.objects.order_by("-pub_date")[:5]
    template = loader.get_template("polls/index.html")
    context = {
        "latest_question_list": latest_question_list,
    }
    return HttpResponse(template.render(context, request))

def signup(request):
    if request.method == "POST":
        form = UserCreationForm(request.POST)
        if form.is_valid():
            user = form.save()
            login(request, user)
            return redirect("profile")
    else:
        form = UserCreationForm()
    return render(request, "polls/signup.html", {"form": form})

def signup_success(request):
    return render(request, "polls/signup_success.html")

def signup_success(request):
    return render(request, 'polls/signup_success.html')  # Updated path

def profile(request):
    return render(request, 'polls/profile.html')  # Updated path

def home(request):
    return render(request, 'polls/index.html')  # Home page
