"
How many workers may run at once for the lanes that draw on me: a count of places, and
nothing that holds a process.

Every lane of a queue draws on one pool, and several lanes may share one -- by default
all of them share one, and then my size is the upper bound of the whole queue. A lane
that is to have workers of its own gets a pool of its own, so that a lane full of due
work cannot take the places another lane needs.

Which places are taken I do not count myself. The queue counts them off its running
workers, so there is no second count that a worker ending the hard way could leave
behind. Like the lanes I am built at every start and never stored.
"
Class {
	#name : #SoilQueueWorkerPool,
	#superclass : #Object,
	#instVars : [
		'name',
		'size'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueWorkerPool class >> named: aSymbol size: anInteger [

	^ self new
		setName: aSymbol;
		size: anInteger;
		yourself
]

{ #category : #accessing }
SoilQueueWorkerPool >> name [

	^ name
]

{ #category : #printing }
SoilQueueWorkerPool >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << name << ' ' << size printString
]

{ #category : #initialization }
SoilQueueWorkerPool >> setName: aSymbol [

	name := aSymbol
]

{ #category : #accessing }
SoilQueueWorkerPool >> size [
	"how many workers of my lanes may run at once"

	^ size
]

{ #category : #accessing }
SoilQueueWorkerPool >> size: anInteger [

	anInteger < 1 ifTrue: [ ^ self error: 'a pool with no place would never let a worker run' ].
	size := anInteger
]
