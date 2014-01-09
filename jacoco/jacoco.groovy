// Example of usage:
// $ groovy -cp jacocoant.jar:/home/mistria/.m2/repository/org/apache/ant/ant/1.8.4/ant-1.8.4.jar jacococ.groovy org.jboss.tools.openshift

import org.apache.ivy.ant.AddPathTask;
import org.apache.tools.ant.Project;
import org.apache.tools.ant.types.FileSet
import org.apache.tools.ant.types.resources.FileResource

filter = (String)args[0]

Project p = new Project()
report = new org.jacoco.ant.ReportTask()
parentGroup = report.createStructure()
parentGroup.setName("JBoss Tools")
group = parentGroup.createGroup()
group.setName(filter)

isMavenModule = { folder ->
	new File(folder, "pom.xml").exists()
}

jarFiles = group.createClassfiles()
allJars = [] as Set
addSurefireRuntimeJars = { testDir ->
   File configFile = new File(testDir, "target/work/configuration/config.ini")
   FileInputStream stream = new FileInputStream(configFile)
   Properties props = new Properties()
   props.load(stream)
   stream.close()
   allJars.addAll(props.get("osgi.bundles").split(",").findAll({ref -> ref.contains(filter) && ref.endsWith(".jar")}).collect({ ref ->
	   new File(((String)ref).substring("reference:file:".size()));
   }))
}
new File("tests").listFiles().findAll(isMavenModule).each(addSurefireRuntimeJars)
new File(".").listFiles().each { module ->
	new File(module, "tests").listFiles().findAll(isMavenModule).each(addSurefireRuntimeJars)
}

allJars.each { f ->
	jarFiles.add(new FileResource(f))
}

sourceFiles = group.createSourcefiles()
addPluginSource = { plugin ->
	sourceFiles.add(new FileResource(new File(plugin, "src")));
}
new File("plugins").listFiles().findAll(isMavenModule).each(addPluginSource);
new File(".").listFiles().each { module ->
	new File(module, "plugins").listFiles().findAll(isMavenModule).each(addPluginSource)
}

exectionData = report.createExecutiondata()
def jacocoExec = new File("target/jacoco.exec")
exectionData.add(new org.apache.tools.ant.types.resources.FileResource(jacocoExec))
report.createHtml().setDestdir(new File("target/coverage-report/html"))
report.createXml().setDestfile(new File("target/coverage-report/coverage-report.xml"))
report.createCsv().setDestfile(new File("target/coverage-report/coverage-report.csv"))

report.setProject(p)
report.init()
report.execute()
