import requests
from github import Github

g = Github("username", "password")

output = ""
libraries = []
header = ""
with open('library_list.txt', 'r') as f:
    line = f.readline()
    while line:
        target_library = line.strip()
        libraries.append(target_library)
        line = f.readline()
    f.close()

for target_library in libraries:
    repositories = g.search_repositories(query=target_library+' language:swift')
    org = repositories[0].full_name.split('/')[0]

    header += "<b>・{}</b> by {}<br>".format(target_library,org)
    for tail in ["",".md"]: #LICENSE / LICENSE.mdどっちかのパターンがあるっぽい
        license_url = 'https://raw.githubusercontent.com/' + repositories[0].full_name +'/master/LICENSE' + tail
        print(repositories)
        print(license_url)

        req = requests.get(license_url)
        if req.status_code == 200:
            raw_license = req.text
            output += "<h1>{}</h1><br>{}".format(target_library, raw_license) + '<br>'*4
        # else:
            # print("**ERROR!**≠\nstatus code: not 200⇛",license_url)

output = header + "<br>"*4 + output
with open('COMBINED_LICENSE', mode='w') as f:
    f.write(output)
