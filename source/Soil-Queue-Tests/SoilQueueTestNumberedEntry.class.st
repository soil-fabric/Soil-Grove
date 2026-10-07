"
An entry that writes its number on its target when it runs, so that a test can read off
the order in which entries were worked.
"
Class {
	#name : #SoilQueueTestNumberedEntry,
	#superclass : #SoilQueueTestEntry,
	#instVars : [
		'number'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestNumberedEntry class >> on: aTarget number: anInteger [

	^ (self on: aTarget)
		setNumber: anInteger;
		yourself
]

{ #category : #working }
SoilQueueTestNumberedEntry >> performIn: aTransaction [

	self target addEffect: number.
	^ #finished
]

{ #category : #initialization }
SoilQueueTestNumberedEntry >> setNumber: anInteger [

	number := anInteger
]
