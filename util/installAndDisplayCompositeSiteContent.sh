#!/bin/bash

# this Jenkins script is used to install a comma-separated list of IUs (.feature.groups) from a composite site into a pre-existing Eclipse installation, then diff 
# whether the fresh installation differs from a previously cached install manifest (list of features/plugins)
# if the install footprint is different from before, the composite site contains new content and we should fire a downstream job to produce a new aggregate site

usage ()
{
	echo "Usage: $0 -PATH path/to/composite/ -SITES http://target-platform-site,http://composite-site/ -IUs a.feature.group,b.feature.group"
	echo "Example: $0 -PATH builds/staging/_composite_/core/trunk/ -SITES http://download.jboss.org/jbosstools/updates/kepler/,http://download.jboss.org/jbosstools/builds/staging/_composite_/core/trunk/ -IUs org.hibernate.eclipse.feature.feature.group,org.jboss.ide.eclipse.archives.feature.feature.group,..."
	exit 1;
}

if [[ $# -lt 1 ]]; then
	usage;
fi

#defaults
PATH="builds/staging/_composite_/core/trunk/"
SITES="http://download.jboss.org/jbosstools/updates/kepler/,http://download.jboss.org/jbosstools/builds/staging/_composite_/core/trunk/"
IUs="org.hibernate.eclipse.feature.feature.group,org.jboss.ide.eclipse.archives.feature.feature.group,org.jboss.ide.eclipse.as.feature.feature.group,org.jboss.ide.eclipse.freemarker.feature.feature.group,org.jboss.tools.cdi.deltaspike.feature.feature.group,org.jboss.tools.cdi.feature.feature.group,org.jboss.tools.cdi.seam.feature.feature.group,org.jboss.tools.common.jdt.feature.feature.group,org.jboss.tools.common.mylyn.feature.feature.group,org.jboss.tools.community.central.feature.feature.group,org.jboss.tools.community.project.examples.feature.feature.group,org.jboss.tools.forge.feature.feature.group,org.jboss.tools.jmx.feature.feature.group,org.jboss.tools.jsf.feature.feature.group,org.jboss.tools.jst.feature.feature.group,org.jboss.tools.maven.cdi.feature.feature.group,org.jboss.tools.maven.feature.feature.group,org.jboss.tools.maven.hibernate.feature.feature.group,org.jboss.tools.maven.jbosspackaging.feature.feature.group,org.jboss.tools.maven.jdt.feature.feature.group,org.jboss.tools.maven.portlet.feature.feature.group,org.jboss.tools.maven.profiles.feature.feature.group,org.jboss.tools.maven.project.examples.feature.feature.group,org.jboss.tools.maven.seam.feature.feature.group,org.jboss.tools.maven.sourcelookup.feature.feature.group,org.jboss.tools.openshift.egit.integration.feature.feature.group,org.jboss.tools.openshift.express.feature.feature.group,org.jboss.tools.portlet.feature.feature.group,org.jboss.tools.project.examples.feature.feature.group,org.jboss.tools.richfaces.feature.feature.group,org.jboss.tools.runtime.core.feature.feature.group,org.jboss.tools.runtime.seam.detector.feature.feature.group,org.jboss.tools.seam.feature.feature.group,org.jboss.tools.usage.feature.feature.group,org.jboss.tools.vpe.browsersim.feature.feature.group,org.jboss.tools.vpe.feature.feature.group,org.jboss.tools.ws.feature.feature.group,org.jboss.tools.ws.jaxrs.feature.feature.group"
DESTINATION="tools@filemgmt.jboss.org:/downloads_htdocs/tools"
DEST_URL="http://download.jboss.org/jbosstools"
manifest=composite.site.IUs.txt

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-PATH') PATH="$2"; shift 1;;
		'-SITES') SITES="$2"; shift 1;;
		'-IUs') IUs="$2"; shift 1;;
		'-DESTINATION') DESTINATION="$2"; shift 1;;
		'-DEST_URL') DEST_URL="$2"; shift 1;;
	esac
	shift 1
done

cd ${WORKSPACE}

# get previous manifest file, if it exists
rm -f ${manifest}_PREVIOUS
wget -q ${DEST_URL}/${PATH}/${manifest} -O ${manifest}_PREVIOUS --no-check-certificate -N
touch ${manifest}_PREVIOUS 

# run scripted installation via p2.director
rm -f ${WORKSPACE}/director.xml
wget ${DEST_URL}/updates/scripted-installation/director.xml -q --no-check-certificate -N
chmod +x ${WORKSPACE}/eclipse/eclipse
${WORKSPACE}/eclipse/eclipse -consolelog -nosplash -data /tmp -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml -DtargetDir=${WORKSPACE}/eclipse \
 -DsourceSites=${SITES} -DIUs=${IUs} 

# collect a list of IUs in the installation - if Eclipse version or any included IUs change, this will change and cause downstream to spin. THIS IS GOOD.
find ${WORKSPACE}/eclipse/features/ ${WORKSPACE}/eclipse/plugins/ -maxdepth 1 -type f | tee ${manifest}

# update cached copy of the manifest for subsequent checks
rsync -arzq --protocol=28 ${manifest} ${DESTINATION}/${PATH}/

# echo a string to the Jenkins console log which we can then search for using Jenkins Text Finder to determine if the build should be blue (STABLE) or yellow (UNSTABLE)
if [[ `diff ${manifest} ${manifest}_PREVIOUS` ]]; then
  echo "COMPOSITE HAS CHANGED" 	# mark build stable (blue) and fire downstream job
else
  echo "COMPOSITE UNCHANGED" 	# mark build unstable (yellow) and do not fire downstream job
fi
