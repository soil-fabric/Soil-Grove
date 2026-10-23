"
An entry for a grouped lane: it says its group, given when it is made. A real one would
read it off its target.
"
Class {
	#name : #SoilQueueTestGroupedEntry,
	#superclass : #SoilQueueTestEntry,
	#instVars : [
		'groupId'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestGroupedEntry class >> on: anObject group: anInteger [

	^ (self on: anObject)
		setGroupId: anInteger;
		yourself
]

{ #category : #accessing }
SoilQueueTestGroupedEntry >> groupId [

	^ groupId
]

{ #category : #initialization }
SoilQueueTestGroupedEntry >> setGroupId: anInteger [

	groupId := anInteger
]
