"
A queue that remembers every worker its dispatcher started. The running workers are a
moment's picture: a forked worker can work its way through and be gone again before a
test reads them. What was started stays.
"
Class {
	#name : #SoilQueueTestRecordingQueue,
	#superclass : #SoilQueue,
	#instVars : [
		'started'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestRecordingQueue class >> from: aQueue [
	"the same queue, only recording. A live queue comes from its description, and the
	description knows one class to make"

	^ self basicNew
		copyFrom: aQueue;
		initializeStarted;
		yourself
]

{ #category : #initialization }
SoilQueueTestRecordingQueue >> initializeStarted [

	started := OrderedCollection new
]

{ #category : #accessing }
SoilQueueTestRecordingQueue >> started [
	"every worker started so far, running or not"

	^ started asArray
]

{ #category : #running }
SoilQueueTestRecordingQueue >> workerStarting: aWorker [

	super workerStarting: aWorker.
	started add: aWorker
]
