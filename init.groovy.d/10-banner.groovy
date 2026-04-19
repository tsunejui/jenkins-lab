import jenkins.model.Jenkins

def line = "=" * 60
println line
println "[init.groovy.d] Jenkins Lab boot hook @ ${new Date()}"
println "[init.groovy.d] Jenkins version : ${Jenkins.instance.version}"
println "[init.groovy.d] JENKINS_HOME    : ${Jenkins.instance.rootDir}"
println line
