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
	checks its own packages itself; what is unchecked until this says so is ours. A queue
	is never written -- it is a resident, and only its description is stored -- but should
	it end up in a written graph by accident, its mutex, its in-flight set and its live
	lanes must not go along, and the declaration is what keeps them out."

	^ { SoilQueueEntry package }
]

{ #category : #tests }
SoilQueueCleanCodeTest >> testEveryEntryThatCanWorkSaysWhatHoldsAfterAnAbort [
	"#resumeAfterAbortIn: has no default, and a subclass that forgets it would not find out
	before its first orphan -- after a crash, where the queue can only report it and leave
	the entry claimed. Asked here of every subclass that can be put to work, whatever its
	package: one that cannot work yet is there to be subclassed, and says nothing about the
	work either. Only where this package is loaded, though -- a project that loads the
	queue without its tests asks its own subclasses itself"

	self assertEmpty: (SoilQueueEntry allSubclasses select: [ :each |
		(each lookupSelector: #performIn:) isAbstract not and: [
			(each lookupSelector: #resumeAfterAbortIn:) isAbstract ] ])
]

{ #category : #tests }
SoilQueueCleanCodeTest >> testTheQueueKeepsTheTransientsItInherits [
	"a declaration of mine replaces the inherited one rather than adding to it, so a queue
	that forgot them would write its supervisor and its process along"

	self assert: (SoilQueue soilTransientInstVars includesAll: SoilActiveResident soilTransientInstVars)
]
