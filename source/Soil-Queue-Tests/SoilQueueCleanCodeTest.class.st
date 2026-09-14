"
The structural checks Soil applies to its own packages, pointed at Soil-Queue. Without
this the new package sits outside every one of them: #packageToCheck resolves upwards to
Soil-Core, so the rules would run twice over Soil and never over us.

I inherit from Soil-Resident's version rather than from SoilCleanCodeTest, because the
three things Soil-Resident had to add are the same three things here -- two rules that
are inherited as `self skip` for known violations the new packages do not have, and the
check for references that a fully loaded development image resolves and a build does not.
Copying them a second time is how they would drift apart.
"
Class {
	#name : #SoilQueueCleanCodeTest,
	#superclass : #SoilResidentCleanCodeTest,
	#category : #'Soil-Queue-Tests'
}

{ #category : #testing }
SoilQueueCleanCodeTest class >> shouldInheritSelectors [
	"a concrete TestCase inherits no test selectors from a concrete superclass, so without
	this the rules would not run against this package at all"

	^ true
]

{ #category : #running }
SoilQueueCleanCodeTest >> packageToCheck [

	^ SoilQueueEntry package
]

{ #category : #running }
SoilQueueCleanCodeTest >> soilTransientDeclarationPackages [
	"the two transient-declaration checks look here rather than at #packageToCheck. Soil
	checks its own packages itself; what is unchecked until this says so is ours -- and a
	queue is exactly the kind of persisted object that needs the declaration, because its
	mutex, its in-flight set and its rate counter must not be written."

	^ { SoilQueueEntry package }
]
