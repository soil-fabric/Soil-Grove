"
A clock that stands still until it is told to move. The queue asks it for the time
instead of asking DateAndTime, so a test can say 'an hour later' without waiting an hour
-- and without the flakiness of a test that sleeps and hopes the scheduler agrees.
"
Class {
	#name : #SoilQueueTestClock,
	#superclass : #Object,
	#instVars : [
		'now'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestClock class >> at: aDateAndTime [

	^ self new
		setNow: aDateAndTime;
		yourself
]

{ #category : #moving }
SoilQueueTestClock >> advanceBy: aDuration [

	now := now + aDuration
]

{ #category : #accessing }
SoilQueueTestClock >> now [

	^ now
]

{ #category : #initialization }
SoilQueueTestClock >> setNow: aDateAndTime [

	now := aDateAndTime
]
