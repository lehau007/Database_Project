from django.shortcuts import render, get_object_or_404
from .models import Question, TestCase
from django.http import JsonResponse
import http.client
import json
import time

RAPIDAPI_HOST = "judge029.p.rapidapi.com"
RAPIDAPI_KEY = "e7238605d0mshf1055b263943c90p1dd460jsnc7a3d80e9ff9"  # Replace with your RapidAPI key

code = "#include <stdio.h>\nint main() { printf(\"Hello, World!\\n\"); return 0; }"
language_id = 52  # Language ID for C (example)
testcase = ["Input data for testing"]

token = submit_code_to_judge0(code, language_id, testcase[0])
print(token)

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
    print("Submit Code Response:", response_json)  # Add print here

    if "token" in response_json:
        return response_json['token']
    return None
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

    response_json = json.loads(data.decode("utf-8"))
    return response_json

# Main view to handle question submission and code execution
def question_with_editor(request, question_id):
    # Fetch the question using the dynamic question_id from the URL
    question = get_object_or_404(Question, question_id=question_id)

    # Split content by newline (\n) for the template
    description_lines = question.description.replace(r'\n', '\n').splitlines()
    input_lines = question.input.replace(r'\n', '\n').splitlines()
    output_lines = question.output.replace(r'\n', '\n').splitlines()
    constraints_lines = question.constraints.replace(r'\n', '\n').splitlines()
    example_lines = question.example.replace(r'\n', '\n').splitlines()

    if request.method == 'POST':
        # Handle form submission for code execution
        code = request.POST.get('code', '')  # Code entered by the user
        language_id = int(request.POST.get('language_id', 54))  # Default to C++

        # Fetch related test cases for the question
        testcases = TestCase.objects.filter(question_id=question_id)
        print(f"Here is number of testcases: {len(testcases)}")
        results = []

        if not testcases:
            return JsonResponse({'error': 'No test cases found for this question'}, status=404)

        # Loop through test cases to submit code and check results
        for testcase in testcases:
            # Submit code to Judge0
            token = submit_code_to_judge0(code, language_id, testcase.input)
            if token:
                # Poll for the result until it's completed
                while True:
                    result = get_result_from_judge0(token)
                    if result and result.get('status', {}).get('id') == 3:  # Status 3 means completed
                        actual_output = result.get('stdout', '').strip()
                        expected_output = testcase.output.strip()
                        status = 'Correct' if actual_output == expected_output else 'Wrong'
                        
                        # Add the result to the list of results
                        results.append({
                            'input': testcase.input,
                            'expected': expected_output,
                            'actual': actual_output,
                            'status': status,
                        })
                        break
                    elif result and result.get('status', {}).get('id') in [4, 5]:  # Status 4 or 5 means error
                        results.append({'input': testcase.input, 'error': 'Execution error or timeout'})
                        break
                    time.sleep(2)  # Poll every 2 seconds to check the result
        print(results)
        cnt = 0
        status = 'Failed'
        for result in results:
            if result['status'] == 'Correct':
                cnt = cnt + 1
        if cnt == len(testcases):
            status = 'Accepted'
        elif cnt > 0:
            status = 'Partial'
        else:
            status = 'Failed'
        
        return JsonResponse({'results': results})

    # Render the question with the code editor template
    return render(request, 'problem/question_editor.html', {
        'question': question,
        'description_lines': description_lines,
        'input_lines': input_lines,
        'output_lines': output_lines,
        'constraints_lines': constraints_lines,
        'example_lines': example_lines,
    })

# View to fetch all questions
def questions_list(request):
    questions = Question.objects.all()
    return render(request, 'problem/question_list.html', {'questions': questions})

# View for the homepage
def home(request):
    return render(request, 'home.html')