from django.urls import path
from django.contrib.auth import views as auth_views

"""
from . import views

app_name = "polls"
urlpatterns = [
    path("", views.index, name="index"),
    path("<int:question_id>/", views.detail, name="detail"),
    path("<int:question_id>/results/", views.results, name="results"),
    path("<int:question_id>/vote/", views.vote, name="vote"),
    path('signup/', views.signup, name='signup'),
    path('signup/success/', views.signup_success, name='signup_success'),
    path('profile/', views.profile, name='profile'),
    path('login/', auth_views.LoginView.as_view(template_name='polls/login.html'), name='login'),
    path('logout/', auth_views.LogoutView.as_view(next_page='/login/'), name='logout'),  # Logout URL
]
"""

from django.urls import path
from . import views

urlpatterns = [
    # GENEREL BLOCK
    path('signup/', views.signup_view, name='signup'),
    path('login/', views.login_view, name='login'),
    path('signup_success/', views.signup_success, name='signup_success'),
    path('profile/', views.profile, name='profile'),

    # STUDENT BLOCK
    path('student_dashboard/', views.student_view, name='student_dashboard'),
    path('view_contests/', views.student_view_contest, name='student_view_contest'),
    path('view_contests/questions/', views.student_question_view, name='student_view_question'), 
    path('view_contests/questions/display/<int:question_id>/', views.display_question, name='question_details'),
    path('view_contest/join/', views.join_contest, name='join_contest'),
    

    # ADMIN BLOCK
    path('admin_question/', views.questions_view, name='question'),
    path('admin_dashboard/', views.admin_view, name='admin_dashboard'),
    path('admin_view_contest/', views.admin_view_contest, name='admin_contest'),
    path('add_question/', views.add_question, name='add_question'), 
    path('leadboard/', views.view_leadboard, name='view_leadboard'),
    path('see_statistic/', views.statistic, name='admin_view_statistic'),
    path('admin_view_contest/add_contest/', views.add_contest, name='add_contest'),
    path('question_submission_details/', views.question_submission_details, name='question_submission_details'),
    path('add_view_contest/see_participants/', views.see_participants, name='see_participants'),
]
