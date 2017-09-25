# use this to insert a block of XML into an existing pom 

from optparse import OptionParser
import re
import lxml.etree as ET

usage = "Usage: python -W ignore %prog --file /path/to/pom.xml --parent nodeName --xml \"<block><of xml/></block>\"\n\
\n\
Examples:\n\
\n\
python -W ignore %prog --file /path/to/pom.xml --parent properties --xml \\\n\
  \"<webtools_common_site>https://hudson.eclipse.org/webtools/job/WTP-R3_9_x_Maintenance/lastSuccessfulBuild/artifact/webtools.repositories/\\\n\
repository/target/</webtools_common_site>\"\n\
\n\
python -W ignore %prog --file /path/to/pom.xml --parent repositories --xml \\\n\
  \"<repository><id>webtools_common</id><layout>p2</layout><url>\\${webtools_common_site}</url></repository>\"\n\
"
parser = OptionParser(usage)
parser.add_option("-f", "--file",	dest="xmlfile",   help="path to the pom file to edit")
parser.add_option("-p", "--parent", dest="parent",   help="parent node in which to insert block of XML")
parser.add_option("-x", "--xml",	dest="xml",	  help="XML to insert")
(options, args) = parser.parse_args()

if (not options.xmlfile or not options.parent or not options.xml):
	parser.error("Must specify ALL required commandline flags")

tree = ET.parse(options.xmlfile)
root = tree.getroot()
for node in root:
	if options.parent in str(node.tag): # look for the properties node
		newNode=ET.fromstring(options.xml) # create a new property node to insert into the properties
		newNode.tail = "\n  "
		node.append(newNode)
		# debug inserted node + existing nodes
		#for node in node:
		#	print node.tag, node.attrib

# write changes back to original file
with open(options.xmlfile, "w") as f:
	f.write(ET.tostring(tree, pretty_print=True, xml_declaration=True,
		encoding=tree.docinfo.encoding,
		standalone=tree.docinfo.standalone))

