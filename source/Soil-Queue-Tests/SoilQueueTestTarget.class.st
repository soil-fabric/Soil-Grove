"
The domain object a test entry works on, and the only place the effects of that work are
visible afterwards.

They have to live here rather than on the entry, and not only for tidiness: a finished
entry is taken out of the ordering and nothing refers to it any more, so anything it
recorded goes with it. What the work did to the world outlives the entry that did it --
which is the point the wrapper exists to make.

I am a cluster root of my own, so an entry that refers to me stays small: without that,
reading the entry would materialize me and everything I hold along with it.
"
Class {
	#name : #SoilQueueTestTarget,
	#superclass : #Object,
	#instVars : [
		'effects',
		'compensations'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #testing }
SoilQueueTestTarget class >> isSoilClusterRoot [

	^ true
]

{ #category : #accessing }
SoilQueueTestTarget >> addCompensation: anObject [

	compensations add: anObject
]

{ #category : #accessing }
SoilQueueTestTarget >> addEffect: anObject [

	effects add: anObject
]

{ #category : #accessing }
SoilQueueTestTarget >> compensations [
	"what each cleanup found waiting for it"

	^ compensations asArray
]

{ #category : #accessing }
SoilQueueTestTarget >> effects [
	"everything the work ever did to me, repetitions included"

	^ effects asArray
]

{ #category : #initialization }
SoilQueueTestTarget >> initialize [

	super initialize.
	effects := OrderedCollection new.
	compensations := OrderedCollection new
]

{ #category : #accessing }
SoilQueueTestTarget >> undoLastEffect [

	compensations add: effects size.
	effects isEmpty ifFalse: [ effects removeLast ]
]
