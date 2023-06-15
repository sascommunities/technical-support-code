/* Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

/**
  * This program will find the first cyclical group memberships in SAS Metadata
  * if one exists.
  * e.g. GroupA - memberOf -> GroupB - memeberof -> GroupC -> memberOf -> GroupA
  *
  *   NOTE - Program will stop after finding any 1 cycle. Execute again once 
  *     cycle is addressed in SAS Metadata to ensure none are left.
  *
  *   REQUIREMENTS - Program leverages the Groovy procedure XCMD must be permitted
  *     to execute this program. 
  * 
  * Date: 6 April 2023
  * Sample output:
  *
  *    107          endsubmit;
  *    !! Metadata Group Cycle Found !!
  *    A5JBTWVI.A5000024
  *    A5JBTWVI.A5000025
  *    A5JBTWVI.A5000026
  */

options metaserver = "< SAS METADATA SERVER HOSTNAME>"
        metauser   = "< SAS METADATA SERVER USER>"
        metapass   = "< SAS METADATA SERVER PASSWORD>";

/* Extract from Metadata user and group information into the WORK library */
%mduextr(libref=work)

/* Write the list of all group ids to the vertices file `vert` */
filename verts temp;
data _null_;
  file verts;
  set work.group_info;
  put id;
run;

/* Create the list of edges. i.e. Which group is a member of which */
filename edges temp;
data _null_;
  file edges dlm=',';
  set work.groupmemgroups_info;
  put id memid;
run;

/* Run a Groovy program that reads in the list of vertices and list of edges,
   creates a graph, then traverses this graph to find the first cycle. */
proc groovy;
  submit "%sysfunc(pathname(verts))" "%sysfunc(pathname(edges))" ;

class Vertex {
  String groupid
  List<Vertex> members
  public Vertex (_groupid) {
    groupid=_groupid
    members = new ArrayList<>()
  }
  String toString() { return groupid }
}

class Graph {
  List<Vertex> groups
  public Graph () {
    groups = new ArrayList()
  }
  void addVertex(v) { 
    groups.add(v) 
  }
  void addEdge (from, to) {
    from.members.add(to)
  }
  boolean hasCycle(v, visited, inStack) {
    if (inStack[v]) { return true }
    if (visited[v]) { return false }
    visited[v] = true
    inStack[v] = true
    for (member in v.members) {
      if (hasCycle(member, visited, inStack)) { return true }
    }
    inStack[v] = false
    return false
  }
  boolean hasCycle() {
    def visited = groups.collectEntries { [it, false] }
    def inStack = groups.collectEntries { [it, false] }
    for (group in groups) {
      if (hasCycle(group, visited, inStack)) { 
        println "!! Metadata Group Cycle Found !!"
        inStack.findAll{it.value}.each{ println it.key }
        return true 
      }
    }
    return false
  }
}

/* Parse input vertices file and edge file in lists */
def in_v = new File(args[0]).readLines().unique()
def in_e = new File(args[1]).readLines()*.split(',')

/* Create a new empty graph */
def g = new Graph()

/* Create a map of unique groupid -> Vertex objects */
def V = in_v.unique().collectEntries { [it, new Vertex(it)] }

/* Add all the unique vertices to the graph */
V.values().each{
  g.addVertex(it)
}

/* Add all the edges in the graph */
in_e.each { 
  g.addEdge(V[it[0]],V[it[1]])
}

/* Check if there is a cycle somewhere */
g.hasCycle()

  endsubmit;
quit;
