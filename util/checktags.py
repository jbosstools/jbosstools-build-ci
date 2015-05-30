from github import Github
import sys
import semantic_version
import re
import pprint
from collections import OrderedDict

## sorted to have first match win.
versionmapping = OrderedDict()
versionmapping[re.compile("jbosstools-3.0.(.*)")] = "jbdevstudio-2.0.\\1"
versionmapping[re.compile("jbosstools-3.1.(.*)")] = "jbdevstudio-3.0.\\1"
versionmapping[re.compile("jbosstools-3.2.(.*)")] = "jbdevstudio-4.0.\\1"
versionmapping[re.compile("jbosstools-3.3.(.*)")] = "jbdevstudio-5.0.\\1"
versionmapping[re.compile("jbosstools-4.0.(.*)")] = "jbdevstudio-6.0.\\1"
versionmapping[re.compile("jbosstools-4.1.0.Final")] = "jbdevstudio-7.0.0.GA"
versionmapping[re.compile("jbosstools-4.1.0(.*)")] = "jbdevstudio-7.0.0\\1"
versionmapping[re.compile("jbosstools-4.1.1.Final")] = "jbdevstudio-7.1.0.GA"
versionmapping[re.compile("jbosstools-4.1.1(.*)")] = "jbdevstudio-7.1.0\\1"
versionmapping[re.compile("jbosstools-4.1.2(.*)")] = "jbdevstudio-7.1.1\\1"
versionmapping[re.compile("jbosstools-4.2.2(.*)")] = "jbdevstudio-8.1.0\\1"
versionmapping[re.compile("jbosstools-4.2.(.).Final")] = "jbdevstudio-8.0.\\1.GA"
versionmapping[re.compile("jbosstools-4.2.(.*)")] = "jbdevstudio-8.0.\\1"
versionmapping[re.compile("jbosstools-4.3.(.*)")] = "jbdevstudio-9.0.\\1" 


#repos not following jbt tagging cycle
nondevrepos = [
    "jbosstools-gwt",
    "jbosstools-deltacloud",
    "jbosstools-fuse-extras",
    "jbosstools-devdoc",
    "jbosstools-locus",
    "jbosstools-runtime-soa",
    "jbosstools-maven-plugins",
    "jbosstools-jbpm",
    "jbosstools-esb",
    "jbosstools-documentation",
    "jbosstools-full-svn-mirror",
    "jbosstools-website",
    "m2e-apt",
    "m2e-wro4j",
    "m2e-jdt-compiler",
    "m2e-wtp-tests",
    "jbosstools-integration-tests",
    "jbosstools-integration-stack",
    "jboss-wfk-quickstarts",
    "jbosstools-playground",
    "contacts-mobile-basic-cordova",
    "m2e-polyglot-poc",
    "jbosstools-bpel",
    "jbosstools-integration-stack-tests",
    "jbosstools-xulrunner",
    "jbosstools-install-rinder",
    "jbosstools-target-platforms",
    "jbosstools-central-webpage", ## remove when part of release?
    "incubator-ripple", ## this should be tagged somehow, but how ?
    "jbosstools-versionwatch",
    "jbosstools-archetypes",
    "jbosstools-install-grinder",
    "jbosstools-download.jboss.org",
    "jbdevstudio-devdoc",
    "jbdevstudio-artwork",
    "github-teams",
    "linuxtools-docker",
    "jbdevstudio-ecs",
    "jbdevstudio-website",
    "jbdevstudio-qa"
    ]


## <repo> : <string for first version match sorted by semantic versioning>
since = {
    "jbosstools-base" : "",
    "jbosstools-birt" : "jbosstools-4",
    "jbosstools-build" : "jbosstools-4",
    "jbosstools-build-ci" : "jbosstools-4",
    "jbosstools-build-sites" : "jbosstools-4",
    "jbosstools-central" : "jbosstools-4",
    "jbosstools-download.jboss.org" : "jbosstools-4",
    "jbosstools-forge" : "jbosstools-4.1",
    "jbosstools-javaee" : "",
    "jbosstools-jst" : "",
    "jbosstools-openshift" : "jbosstools-4.1",
    "jbosstools-portlet" : "jbosstools-4",
    "jbosstools-server" : "",
    "jbosstools-vpe" : "",
    "jbosstools-webservices" : "jbosstools-4",
    "jbosstools-freemarker" : "",
    "jbosstools-hibernate" : "",
    "jbosstools-aerogear" : "jbosstools-4.1.0.Alpha2",
    "jbosstools-discovery" : "jbosstools-4",
    "jbosstools-livereload" : "jbosstools-4.2",
    "jbosstools-arquillian" : "jbosstools-4.2",
    "jbosstools-browsersim" : "jbosstools-4.2.0.Beta1",
    "jbdevstudio-product" : "jbdevstudio-7",
    "jbdevstudio-ci" : "jbdevstudio-7",
    }

def jbt_to_devstudio(version):
    for key, match in versionmapping.iteritems():
        if key.match(version):
            v = key.sub(match, version)
            #print match, version, v
            return v
    return version

def find_jbt_versions(g):

  org = g.get_organization("jbosstools")
  therepo = org.get_repo("jbosstools-base")
  
  thetags = []
    
  for tag in therepo.get_tags():
    if tag.name.startswith("jbosstools"):
      thetags.append(tag.name)
    else:
      print "Unexpected tag in jbosstools-base:" + tag.name
      
  thetags.sort()
  return thetags

def map_jbt_to_devstudio_versions(versiontags):
    devstudio = {}
    for v in versiontags:
        jbt = jbt_to_devstudio(v)
        if jbt == v:
            print "Missing devstudio mapping for " + jbt
        devstudio[v] = jbt

    if len(devstudio)!=len(set(devstudio)):
        print "ERROR!"
        sys.exit(0)
    
    return devstudio

def githubcheck(org, thetags, nondevrepos, since):
    "Uses the 'base' named repo to lookup tags and check if they exist on all\
     other repos in the organization. repos in 'nondevrepos' will be skipped and\
     'since' will be used to filter tags that does not apply to that repo."
    
    thetags.sort()
    
    print "Checking each repo in " + org.name + " against " + str(len(thetags)) + " expected tags."

    for repo in org.get_repos():
        if repo.name not in nondevrepos:
            tags = repo.get_tags()
            rawtags = []
            for tag in tags:
                rawtags.append(tag.name)

            sincetags = []
            
            if repo.name in since:
                sincetags = [e for e in thetags if e > since[repo.name]]
            else:
                print "Missing since mapping for " + repo.name
                
            diff = set(sincetags) - set(rawtags)
            if diff:
                diff = sorted(diff)
                diffannotated = []
                for d in diff:
                    branch = None
                    try:
                        branch = repo.get_branch(d + 'x')
                    except:
                        pass # if branch not found we just continue
                    if branch:
                        diffannotated.append(d + " (" + branch.name + ")")
                        expectedsha = branch.commit.sha
                        #answer = raw_input("Create '" + d + "' with sha: '" + expectedsha + "' from " + branch.name + " in '" + repo.name + "' ? ")
                        #if (answer=="y"):
                        #    repo.create_git_ref("refs/tags/" + d , expectedsha)
                        #    print "Tag created!"
                        #else:
                        #    print "Ok - tag not created"
                    else:
                        diffannotated.append(d)
                print "\n" + repo.name + " missing " + str(len(diff)) + " tags: \n  " + ",\n  ".join(diffannotated)

            unexpected = set(rawtags) - set(thetags) - set(sincetags)
            if (unexpected):
                print "\n" + repo.name + " has " + str(len(unexpected)) + " unexpected tags: \n  " + ",\n  ".join(unexpected)

if len(sys.argv) <> 3:
    print "Please specify both username and github password."
    print "Usage: checktags.py <username> <password>"
    sys.exit(-1)
    
g = Github(sys.argv[1], sys.argv[2])

jbt_versions = find_jbt_versions(g)

jbt_to_devstudio = map_jbt_to_devstudio_versions(jbt_versions)

devstudio_versions = jbt_to_devstudio.values()
pprint.pprint(jbt_to_devstudio)

org = g.get_organization("jbosstools")

#githubcheck(org, jbt_versions, nondevrepos, since)

org = g.get_organization("jbdevstudio")
githubcheck(org, devstudio_versions, nondevrepos, since)
