from django.shortcuts import render

from django.http import HttpResponse, HttpResponseRedirect
from django.template import loader
from django.urls import reverse

from django.db import connection
from django.shortcuts import render

from django.http import Http404
from django.shortcuts import get_object_or_404
from django.db.models import F


from django.shortcuts import redirect
from django.contrib import messages

from django.db import IntegrityError

from django.shortcuts import render, redirect
from django.contrib import messages
from django.db import connection

from django.http import JsonResponse

# Global variables 
isLogin = True
isAdmin = True

student_id = 1
current_contest = -1
admin_id = 1

"""---------------------------------------STUDENT BLOCK-----------------------------------------"""
def join_contest(request):
    global isLogin, isAdmin, student_id

    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if isAdmin:
        return render(request, 'polls/protect_student_page.html')
    
    if request.method == "POST":
        data = json.loads(request.body)
        action = data.get('action')
        contest_id = data.get('id')
        
        if action == "accept":
            query = """
                INSERT INTO participants (participant, contest_id, student_id, point)
                VALUES (%s, %s, %s, 0)
            """
            with connection.cursor() as cursor:
                cursor.execute(query, ("Waiting", contest_id, student_id, ))
        elif action == "reject":
            query = """
                DELETE FROM participants
                WHERE student_id = %s AND contest_id = %s
            """
            with connection.cursor() as cursor:
                cursor.execute(query, (student_id, contest_id))
        else:
            return JsonResponse({'message': 'Invalid action'}, status=400)

        return JsonResponse({'message': 'Action processed successfully'})
    
    # Query contests the student has not joined
    available_query = """
        SELECT DISTINCT c.contest_id, c.name
        FROM contest AS c
        LEFT JOIN participants AS p USING (contest_id)
        WHERE c.contest_id NOT IN (
            SELECT contest_id FROM participants WHERE student_id = %s
        )
    """
    with connection.cursor() as cursor:
        cursor.execute(available_query, (student_id,))
        contests = cursor.fetchall()
    contests = [{'id': row[0], 'name': row[1]} for row in contests]

    # Query contests the student has joined and are pending approval
    pending_query = """
        SELECT c.contest_id, c.name
        FROM contest AS c
        JOIN participants AS p USING (contest_id)
        WHERE p.student_id = %s AND p.participant = 'Waiting'
    """
    with connection.cursor() as cursor:
        cursor.execute(pending_query, (student_id,))
        pending_contests = cursor.fetchall()
    pending_contests = [{'id': row[0], 'name': row[1]} for row in pending_contests]

    return render(request, 'polls/join_contest.html', {
        'contests': contests,
        'pending_contests': pending_contests
    })

def student_view(request):
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if isAdmin:
        return render(request, 'polls/protect_student_page.html')
    query = "select (first_name || ' ' || last_name) as name from student where student_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (student_id, ))
        name = cursor.fetchone()
    name = name[0]

    # cnt student
    query = "SELECT COUNT(*) FROM student"
    with connection.cursor() as cursor:
        cursor.execute(query)
        student_count = cursor.fetchone()
    student_count = student_count[0]
    
    # problem_cnt
    query = "SELECT COUNT(*) FROM submission WHERE status = 'Accepted'"
    with connection.cursor() as cursor:
        cursor.execute(query)
        solved_problem_cnt = cursor.fetchone()
    solved_problem_cnt = solved_problem_cnt[0]

    query = "SELECT COUNT(*) FROM submission"
    with connection.cursor() as cursor:
        cursor.execute(query)
        sub_cnt = cursor.fetchone()
    sub_cnt = sub_cnt[0]

    # Contest this week
    query = "SELECT DATE(created_at) AS submission_date, status, COUNT(*) AS count FROM submission WHERE created_at >= CURRENT_DATE - INTERVAL '7 days' GROUP BY DATE(created_at), status ORDER BY submission_date, status;"
    with connection.cursor() as cursor:
        cursor.execute(query)
        contest_report = cursor.fetchall()

    query = "SELECT COUNT(*) FROM question WHERE level_id = 3"
    with connection.cursor() as cursor:
        cursor.execute(query)
        hard_cnt = cursor.fetchone()
    hard_cnt = hard_cnt[0]

    query = "SELECT COUNT(*) FROM question WHERE level_id = 2"
    with connection.cursor() as cursor:
        cursor.execute(query)
        medium_cnt = cursor.fetchone()
    medium_cnt = medium_cnt[0]


    query = "SELECT COUNT(*) FROM question WHERE level_id = 1"
    with connection.cursor() as cursor:
        cursor.execute(query)
        easy_cnt = cursor.fetchone()
    easy_cnt = easy_cnt[0]

    chart_data = [
        {"value": 700, "name": "Easy", "color": "#28a745"},
        {"value": 400, "name": "Medium", "color": "#ffc107"},
        {"value": 200, "name": "Hard", "color": "#dc3545"}
    ]
    
    return render(request, 'polls/student_dashboard.html', {
        'name': name,
        'student_cnt': student_count, 
        'solved_problem_cnt': solved_problem_cnt, 
        'chart_data': chart_data,
        'sub_cnt': sub_cnt,
    })

def student_view_contest(request):
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if isAdmin:
        return render(request, 'polls/protect_student_page.html')

    global student_id

    query = "SELECT c.contest_id, c.name FROM contest AS c JOIN participants AS p USING (contest_id) WHERE p.student_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (student_id, ))
        contests = cursor.fetchall()  # Fetch all contest rows

    # Convert data into a list
    contest_list = [{"id": row[0], "name": row[1]} for row in contests]

    # Pass data to template
    return render(request, 'polls/view_contest_student.html', {'contests': contest_list})

def student_question_view(request):
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if isAdmin:
        return render(request, 'polls/protect_student_page.html')
    
    global student_id, current_contest
    info = request.GET.get('info')  # Get info from URL

    current_contest = info 
    query = "SELECT q.question_id, q.title, l.name, pq.point, pq.is_accepted FROM question_contest AS qc JOIN question AS q USING (question_id) LEFT JOIN participant_question AS pq on (pq.contest_id = qc.contest_id AND pq.question_id = qc.question_id AND pq.student_id = %s) JOIN level AS l ON q.level_id = l.level_id WHERE qc.contest_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (student_id, info, ))
        contest_data = cursor.fetchall()  # Fetch contest details
        
    question = [{"id": row[0], "name": row[1], "level": row[2], "point": row[3], "isAccept": row[4]} for row in contest_data]
    # print(question)

    # Handle contest_data and render to a template
    return render(request, 'polls/question_in_contest_student.html', {'question': question})

def display_question(request, question_id):
    global student_id, isAdmin, isLogin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if isAdmin:
        return render(request, 'polls/protect_student_page.html')
    
    global student_id, current_contest

    if request.method == 'POST':
        code = request.POST.get('code', '')
        language_id = int(request.POST.get('language_id', 54))  # Default to C++
        
        # Fetch test cases using raw SQL
        testcases_query = "SELECT input, output, test_point FROM test_case WHERE question_id = %s"
        testcases = execute_raw_sql(testcases_query, [question_id])

        if not testcases:
            return JsonResponse({'error': 'No test cases found for this question'}, status=404)

        results = []

        # Loop through test cases to submit code and check results
        for testcase in testcases:
            token = submit_code_to_judge0(code, language_id, testcase[0])
            if token:
                while True:
                    result = get_result_from_judge0(token)
                    if result and result.get('status', {}).get('id') == 3:  # Status 3 means completed
                        actual_output = result.get('stdout', '').strip()
                        expected_output = testcase[1].strip()
                        print("hau1", actual_output)
                        status = 'Correct' if actual_output == expected_output else 'Wrong'
                        results.append({
                            'input': testcase[0],
                            'expected': expected_output,
                            'actual': actual_output,
                            'point': testcase[2],
                            'status': status,
                        })
                        break
                    elif result and result.get('status', {}).get('id') in [4, 5]:  # Error or timeout
                        results.append({'input': testcase[0], 'error': 'Execution error or timeout', 'point': 0})
                        break
                    time.sleep(2)  # Poll every 2 seconds

        # Determine overall status
        correct_count = sum(1 for result in results if result.get('status') == 'Correct')
        points = 0
        for result in results:
            points += results.get('point')

        if correct_count == len(testcases):
            status = 'Accepted'
        elif correct_count > 0:
            status = 'Partial'
        else:
            status = 'Failed'
        
        print(status, points)
        query = "INSERT INTO submission (student_id, question_id, contest_id, evaluation_point, status) VALUES (%s, %s, %s, %s, %s)"
        if current_contest != -1:
            execute_raw_sql(query, [student_id, question_id, current_contest, points, status])
    
    query = "SELECT q.question_id, q.title, q.description FROM question as q where q.question_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (question_id, ))
        datas = cursor.fetchall()  # Fetch contest details
        
    questions = [{"id": data[0], "name": data[1], "description": data[2]} for data in datas]
    questions = questions[0]

    query = "Select s.* from submission as s where s.question_id = %s and s.student_id = %s and s.contest_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (question_id, student_id, current_contest, ))
        data = cursor.fetchall()
        
    submissions = [{"code": row[0], "time": row[4], "point": row[5], "status": row[6]} for row in data]
    # Handle contest_data and render to a template

    # Render the question with the code editor template
    return render(request, 'polls/display_question_form.html', {
        'question': questions,
        'submissions': submissions
    })

"""___________________________________________________________________________________"""

"""-------------------------GENEREL BLOCK----------------------------"""
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
        
        messages.success(request, "Account successfully created. Redirecting...")

        # Redirect to the login page with a success message
        return redirect('/polls/signup_success/')

    return render(request, 'polls/signup.html')

def signup_success(request):
    return render(request, 'polls/signup_success.html')  # Updated path

def profile(request):
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if isAdmin:
        if request.method == "POST":
            current_password = request.POST.get('currentPassword')
            new_password = request.POST.get('newPassword')
            renew_password = request.POST.get('renewPassword')

            query = "select password from profesor where prof_id = %s"
            with connection.cursor() as cursor:
                cursor.execute(
                    query,
                    (admin_id, )
                )
                password = cursor.fetchone()
            
            password = password[0]
            if current_password != password:
                return render(request, 'polls/wrong_current_pass.html')

            if new_password != renew_password:
                return render (request, 'polls/wrong_password.html')
            
            query = "UPDATE professor set password = %s where prof_id = %s"
            with connection.cursor() as cursor:
                cursor.execute(
                    query,
                    (new_password, admin_id, )
                )
            
        query = "SELECT prof_id, (first_name || last_name) as name from professor where prof_id = %s"
        with connection.cursor() as cursor:
            cursor.execute(
                query,
                (admin_id, )
            )
            admin_name = cursor.fetchall()
            
        admin_name = [{"name": row[1]} for row in admin_name]
        # print(admin_name)
        
        return render(request, 'polls/users_profile.html', {"admin_name": admin_name})  # Updated path
    else:
        return render(request, 'polls/student_profile.html')

def home(request):
    return render(request, 'polls/index.html')  # Home page

def login_view(request):
    global student_id, isAdmin, isLogin
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')

        username, kind = username[:len(username) - 3], username[len(username) - 3:]
        
        if kind == '.sv':
            # Custom database query to validate user
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT student_id FROM student WHERE username = %s AND password = %s",
                    [username, password]
                )
                user = cursor.fetchone()
    
            if user:
                # Successful login: Redirect to profile page
                isLogin = True
                isAdmin = False
                student_id = user[0]
                return HttpResponseRedirect('/polls/profile/')
            else:
                # Failed login: Render login page with error message
                return render(request, 'login.html', {
                    'error': 'Invalid username or password.'
                })
        else:
            # Custom database query to validate user
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT prof_id FROM professor WHERE username = %s AND password = %s",
                    [username, password]
                )
                user = cursor.fetchone()
    
            if user:
                # Successful login: Redirect to profile page
                isLogin = True
                isAdmin = True

                admin_id = user[0]
                return HttpResponseRedirect('/polls/profile/')
            else:
                # Failed login: Render login page with error message
                return render(request, 'login.html', {
                    'error': 'Invalid username or password.'
                })

    # For GET requests, render the login page
    return render(request, 'login.html')

"""__________________________________________________________________________________"""


"""--------------------------------ADMIN BLOCK----------------------------------"""
def admin_view_contest(request):
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')
    
    query = "SELECT c.contest_id, c.name FROM contest AS c where c.prof_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (admin_id, ))
        contests = cursor.fetchall()  # Fetch all contest rows

    # Convert data into a list
    contest_list = [{"id": row[0], "name": row[1]} for row in contests]

    # Pass data to template
    return render(request, 'polls/view_contest.html', {'contests': contest_list})

def questions_view(request):
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')

    info = request.GET.get('info')  # Get info from URL
    current_contest = info

    query = "SELECT q.question_id, q.title FROM question_contest AS qc JOIN question AS q USING (question_id) WHERE qc.contest_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (info, ))
        contest_data = cursor.fetchall()  # Fetch contest details
        
    question = [{"id": row[0], "name": row[1]} for row in contest_data]

    # Handle contest_data and render to a template
    return render(request, 'polls/question_in_contest.html', {'question': question})

def add_contest(request):
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')

    return render(request, 'polls/add_contest.html')

def admin_view(request):
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')
    """
    - Participants | this month will change to Participants | All

SELECT COUNT(*) FROM student

-- Problems Solved | this month will change to Problem Solved | All
SELECT COUNT(*)
FROM submission
WHERE status = 'Accepted'

-- Submissions | All

SELECT COUNT(*)
FROM submission

-- Contest Reports | This week

SELECT 
    DATE(created_at) AS submission_date, 
    status, 
    COUNT(*) AS count
FROM submission
WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(created_at), status
ORDER BY submission_date, status;
"""
    # cnt student
    query = "SELECT COUNT(*) FROM student"
    with connection.cursor() as cursor:
        cursor.execute(query)
        student_count = cursor.fetchone()
    student_count = student_count[0]
    
    # problem_cnt
    query = "SELECT COUNT(*) FROM submission WHERE status = 'Accepted'"
    with connection.cursor() as cursor:
        cursor.execute(query)
        solved_problem_cnt = cursor.fetchone()
    solved_problem_cnt = solved_problem_cnt[0]

    # Contest this week
    query = "SELECT DATE(created_at) AS submission_date, status, COUNT(*) AS count FROM submission WHERE created_at >= CURRENT_DATE - INTERVAL '7 days' GROUP BY DATE(created_at), status ORDER BY submission_date, status;"
    with connection.cursor() as cursor:
        cursor.execute(query)
        contest_report = cursor.fetchall()

    query = "SELECT COUNT(*) FROM question WHERE level_id = 3"
    with connection.cursor() as cursor:
        cursor.execute(query)
        hard_cnt = cursor.fetchone()
    hard_cnt = hard_cnt[0]

    query = "SELECT COUNT(*) FROM question WHERE level_id = 2"
    with connection.cursor() as cursor:
        cursor.execute(query)
        medium_cnt = cursor.fetchone()
    medium_cnt = medium_cnt[0]


    query = "SELECT COUNT(*) FROM question WHERE level_id = 1"
    with connection.cursor() as cursor:
        cursor.execute(query)
        easy_cnt = cursor.fetchone()
    easy_cnt = easy_cnt[0]

    # print(easy_cnt, medium_cnt, hard_cnt)
    chart_data = [
        {"value": 700, "name": "Easy", "color": "#28a745"},
        {"value": 400, "name": "Medium", "color": "#ffc107"},
        {"value": 200, "name": "Hard", "color": "#dc3545"}
    ]

    query = "SELECT COUNT(*) FROM submission"
    with connection.cursor() as cursor:
        cursor.execute(query)
        sub_cnt = cursor.fetchone()
    sub_cnt = sub_cnt[0]

    return render(request, 'polls/new_admin_dashboard.html', {
        'student_cnt': student_count, 
        'solved_problem_cnt': solved_problem_cnt, 
        'chart_data': chart_data,
        'sub_cnt': sub_cnt,
    })

def add_question(request):
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')
    
    if request.method == "POST":
        question_title = request.POST.get("questionTitle")
        question_description = request.POST.get("questionDescription")
        test_cases = []
        for i in range(6):
            tc_input = request.POST.get(f"testCases[{i}][input]")
            tc_output = request.POST.get(f"testCases[{i}][output]")

            if tc_input and tc_output:
                test_cases.append([tc_input, tc_output])

        # Create a new question in the database
        query = "INSERT INTO QUESTION (title, description, level_id, prof_id) VALUES (%s, %s, 1, %s)"
        with connection.cursor() as cursor:
            cursor.execute(query, (question_title, question_description, admin_id, ))

        query = "SELECT question_id FROM question where title = %s and description = %s and prof_id = %s"
        with connection.cursor() as cursor:
            cursor.execute(query, (question_title, question_description, admin_id, ))
            contest_data = cursor.fetchone()  # Fetch contest details

        question_id = contest_data[0]

        for input_key, output_key in test_cases:
            test_input = request.POST.get(input_key)
            test_output = request.POST.get(output_key)
            
            query = "INSERT INTO test_case (input, output, question_id, point) VALUES (%s, %s, %s, 10)"
            
            with connection.cursor() as cursor:
                cursor.execute(query, (test_input, test_output, question_id, ))
                contest_data = cursor.fetchone()  # Fetch contest details
        
        query = "INSERT INTO question_contest (question_id, contest_id) VALUES (%s, %s)"
        with connection.cursor() as cursor:
            cursor.execute(query, (question_id, current_contest))
        
        return JsonResponse({"message": "Question added into contest successfully!", "test_cases": test_cases})

    # Render the form page for GET requests
    return render(request, "polls/add_question_2.html")


def view_leadboard(request):
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')
    
    query = "Select (s.first_name || s.last_name), p.point as name from participants as p join student as s using (student_id) where p.contest_id = %s order by (p.point) Desc"
    with connection.cursor() as cursor:
        cursor.execute(query, (current_contest, ))
        datas = cursor.fetchall()
    
    i = 1
    data = []
    for d in datas:
        data.append({'id': i, 'name': d[0], 'point': d[1]})
        i += 1
    
    # print(data)

    return render(request, 'polls/leaderboard.html', {"datas": data})

def statistic(request):
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')
    
    return render(request, 'polls/admin_see_statistic.html')

def question_submission_details(request):
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')
    
    return render(request, 'forld.html')

def see_participants(request):
    if request.method == "POST":
        import json
        data = json.loads(request.body)  # Parse JSON data
        action = data.get("action")
        item_id = data.get("id")
        
        # Process the action and id
        if action == "accept":
            query = "UPDATE participants set participant = %s where student_id = %s"
            with connection.cursor() as cursor:
                cursor.execute(query, ("Accepted", item_id, ))
        elif action == "reject":
            query = "Delete from participants where student_id = %s"
            with connection.cursor() as cursor:
                cursor.execute(query, (item_id, ))
            
    global isLogin, isAdmin, current_contest
    if not isLogin:
        return render(request, 'polls/protect_not_login.html')
    
    if not isAdmin:
        return render(request, 'polls/protect_admin_page.html')
    
    query = "SELECT s.student_id, (s.first_name || s.last_name) as name, p.participant from participants AS p join student AS s using (student_id) where p.contest_id = %s"
    with connection.cursor() as cursor:
        cursor.execute(query, (current_contest, ))
        # print(current_contest)

        contests = cursor.fetchall()  # Fetch all contest rows

    # Convert data into a list
    participants = [{"id": row[0], "name": row[1]} for row in contests if row[2] == 'Accepted']
    pending_participants = [{'id': row[0], "name": row[1]} for row in contests if row[2] != 'Accepted']

    return render(request, 'polls/see_participants.html', {'participants':participants, 'pending_participants':pending_participants})

"""____________________________________TEST_________________________________________________"""

from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from django.db import connection
import http.client
import json
import time

RAPIDAPI_HOST = "judge029.p.rapidapi.com"
RAPIDAPI_KEY = "e7238605d0mshf1055b263943c90p1dd460jsnc7a3d80e9ff9"  # Replace with your RapidAPI key

# Helper function to execute raw SQL
def execute_raw_sql(query, params=None):
    with connection.cursor() as cursor:
        cursor.execute(query, params)
        if query.strip().lower().startswith("select"):
            return cursor.fetchall()
        return None

# Helper function to submit code to Judge0 via http.client
def submit_code_to_judge0(code, language_id, stdin):
    conn = http.client.HTTPSConnection(RAPIDAPI_HOST)
    headers = {
        'x-rapidapi-key': RAPIDAPI_KEY,
        'x-rapidapi-host': RAPIDAPI_HOST,
        'Content-Type': 'application/json'
    }

    payload = json.dumps({
        "source_code": code,
        "language_id": language_id,
        "stdin": stdin
    })

    conn.request("POST", "/submissions", body=payload, headers=headers)
    res = conn.getresponse()
    data = res.read()

    response_json = json.loads(data.decode("utf-8"))
    return response_json.get('token', None)

# Helper function to get result from Judge0 using the token
def get_result_from_judge0(token):
    conn = http.client.HTTPSConnection(RAPIDAPI_HOST)
    headers = {
        'x-rapidapi-key': RAPIDAPI_KEY,
        'x-rapidapi-host': RAPIDAPI_HOST
    }

    conn.request("GET", f"/submissions/{token}", headers=headers)
    res = conn.getresponse()
    data = res.read()

    return json.loads(data.decode("utf-8"))

# Main view to handle question submission and code execution
def question_with_editor(request, question_id):
    # Fetch question details using raw SQL
    question_query = "SELECT * FROM questions WHERE question_id = %s"
    question = execute_raw_sql(question_query, [question_id])

    if not question:
        return JsonResponse({'error': 'Question not found'}, status=404)

    question = question[0]  # Assuming `question_id` is unique
    description_lines = question[2].splitlines()  # Adjust index as per your database schema
    input_lines = question[3].splitlines()
    output_lines = question[4].splitlines()
    constraints_lines = question[5].splitlines()
    example_lines = question[6].splitlines()

    if request.method == 'POST':
        code = request.POST.get('code', '')
        language_id = int(request.POST.get('language_id', 54))  # Default to C++
        
        # Fetch test cases using raw SQL
        testcases_query = "SELECT input, output FROM testcases WHERE question_id = %s"
        testcases = execute_raw_sql(testcases_query, [question_id])

        if not testcases:
            return JsonResponse({'error': 'No test cases found for this question'}, status=404)

        results = []

        # Loop through test cases to submit code and check results
        for testcase in testcases:
            token = submit_code_to_judge0(code, language_id, testcase[0])
            if token:
                while True:
                    result = get_result_from_judge0(token)
                    if result and result.get('status', {}).get('id') == 3:  # Status 3 means completed
                        actual_output = result.get('stdout', '').strip()
                        expected_output = testcase[1].strip()
                        status = 'Correct' if actual_output == expected_output else 'Wrong'
                        results.append({
                            'input': testcase[0],
                            'expected': expected_output,
                            'actual': actual_output,
                            'status': status,
                        })
                        break
                    elif result and result.get('status', {}).get('id') in [4, 5]:  # Error or timeout
                        results.append({'input': testcase[0], 'error': 'Execution error or timeout'})
                        break
                    time.sleep(2)  # Poll every 2 seconds

        # Determine overall status
        correct_count = sum(1 for result in results if result.get('status') == 'Correct')
        if correct_count == len(testcases):
            status = 'Accepted'
        elif correct_count > 0:
            status = 'Partial'
        else:
            status = 'Failed'

        return JsonResponse({'results': results, 'status': status})

    # Render the question with the code editor template
    return render(request, 'problem/question_editor.html', {
        'question': question,
        'description_lines': description_lines,
        'input_lines': input_lines,
        'output_lines': output_lines,
        'constraints_lines': constraints_lines,
        'example_lines': example_lines,
    })

