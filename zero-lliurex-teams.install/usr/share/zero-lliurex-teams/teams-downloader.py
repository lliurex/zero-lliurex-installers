#!/usr/bin/python3
import sys
import time
import tempfile
import requests

def getLastRelease(gitUrl):
	headers = {"Accept": "application/vnd.github.v3+json"}
	response = requests.get(gitUrl, headers=headers)
	response.raise_for_status()
	release = response.json()
	assets = release.get("assets", [])
	url=""
	if len(assets)>0:
		for asset in assets:
			if asset.get("name","").endswith(".deb"):
				url = asset["browser_download_url"]
				break
			
	return(url)
#def getLastRelease

if __name__ == "__main__":
	output=sys.argv[1]
	gitUrl = f"https://api.github.com/repos/IsmaelMartinez/teams-for-linux/releases/latest"
	print("Connecting to {}".format(gitUrl))
	url=getLastRelease(gitUrl)
	print("Last release: {}".format(url.split("/")[-1]))
	if len(url)>0:
		content=requests.get(url,stream=True)
		progressA="Downloading "
		progress=["|","/","-","\\"]
		cont=0
		otime=time.time()
		with open(output,"wb") as f:
			for fchunk in content.iter_content(chunk_size=9082):
				if fchunk!=None:
					f.write(fchunk)
					if time.time()-otime>=0.2:
						out=progressA+progress[int(cont)]
						print(out,end="\r")
						cont+=1
						if cont>=len(progress):
							cont=0
						otime=time.time()
