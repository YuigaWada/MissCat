import requests
from github import Github

g = Github("username", "password")

output = "["
libraries = []
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

    for tail in ["",".md"]: #LICENSE / LICENSE.mdどっちかのパターンがあるっぽい
        license_url = 'https://raw.githubusercontent.com/' + repositories[0].full_name +'/master/LICENSE' + tail
        print(repositories)
        print(license_url)

        req = requests.get(license_url)
        if req.status_code == 200:
            raw_license = req.text
            triple_quote = '"' * 3
            output += "\"{}\": {}\n{}\n{},\n".format(target_library, triple_quote, raw_license, triple_quote)
        # else:
            # print("**ERROR!**≠\nstatus code: not 200⇛",license_url)

output = output[:-2] + "]" # 最後のコロンを無視
with open('COMBINED_LICENSE', mode='w') as f:
    f.write(output)
