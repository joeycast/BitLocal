import UIKit
import SwiftUI
import MapKit
import CoreLocationUI
import Combine

@available(iOS 16.4, *)
struct ContentView: View {
    
    @StateObject private var viewModel = ContentViewModel()
    
    @State public var showingAbout = false
    // @State public var userSearchText = ""
    @State public var elements: [Element]?
    @State public var visibleElements: [Element] = []
    
    @State private var userLocation: CLLocation?
    @State private var cancellable: Cancellable?
    @State private var mapStoppedMovingCancellable: Cancellable?
    @State private var cancellableUserLocation: Cancellable?
    
    let appName = "BitLocal"   
    let apiManager = APIManager()
    
    var body: some View {
        
        // **** Main ZStack ****
        ZStack() {    
            // **** Map ****
            // Sets the map as the background in the ZStack.
            if let elements = elements {
                mapView(elements: elements)
                    .ignoresSafeArea()
                    .onAppear {
                        viewModel.locationManager.requestWhenInUseAuthorization()
                        viewModel.locationManager.startUpdatingLocation()
                    }
            }
            
            // **** Background Header Rectangle ****
            // TODO: Make rectangle more dynamic
            GeometryReader { geometry in 
                let screenSize = geometry.frame(in: .global)
                let screenWidth = screenSize.width
                let roundedRectangleRadius = 10
                
                Rectangle()
                    .cornerRadius(CGFloat(roundedRectangleRadius))
                    .foregroundColor(Color(UIColor.systemBackground)) // Sets the color based on light/dark mode.
                // .frame(width: screenWidth, height: CGFloat(115 + roundedRectangleRadius)) // Use after reintroducing Search
                    .frame(width: screenWidth, height: CGFloat(110 + roundedRectangleRadius)) 
                //.padding(.bottom, CGFloat(roundedRectangleRadius))
                    .padding(.top, -CGFloat(roundedRectangleRadius))
                    .ignoresSafeArea()
            }
            
            // **** Header ****            
            HStack () {
                // **** Title ****
                // Sets the header title.
                Text(appName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .font(.title3)
                    .bold(true)
                    .padding()
                    .padding(.leading, 5)
                // .shadow(radius: 10) // Use if change to logo
                
                // **** About Button ****            
                // Sets about button and toggles showingAbout when tapped. .frame, .contentShape, and .clipShape help increase the tappable area of the button.
                // TODO: How to make iPad cursor snap to button?
                Image(systemName: "info.circle")
                    .padding()
                    .padding(.top, 5)
                    .frame(width: 88, height: 50, alignment: .center)
                    .foregroundColor(.orange)
                //.background(Color.white) // Reveals tappable area (for testing)
                    .contentShape(Circle())
                    .clipShape(Circle())
                    .onTapGesture {
                        showingAbout.toggle()
                    }
                    .frame(maxWidth: 1, maxHeight: .infinity, alignment: .topTrailing) 
            }
            
//            // **** Search Bar ****
//            // Uses GeometryReader to dynamically set search bar position based on device screen size.
//            GeometryReader { geometry in
//                // Use the geometry to determine the size of the screen
//                let screenSize = geometry.frame(in: .global)
//                let screenWidth = screenSize.width
//                
//                HStack {
//                    Image(systemName: "magnifyingglass")
//                        .padding(.leading)
//                    TextField("Search", text: $userSearchText)
//                        .frame(maxWidth: 450, minHeight: 35)
//                }
//                .background(Color(UIColor.systemBackground)) // Sets the color based on light/dark mode.
//                .overlay(
//                    RoundedRectangle(cornerRadius: 10)
//                        .stroke(Color.gray.opacity(0.33), lineWidth: 1)
//                )
//                .padding(.top)
//                .padding(.horizontal)
//                .position(x: screenWidth * 0.5, y: 57)
//            }
            
            // **** Location Button ****            
            // Get current location button. Run requestWhenInUseAuthorization() on tap.
            // TODO: How to make iPad cursor snap to button?
            GeometryReader { geometry in
                // Use the geometry to determine the size of the screen so I can set the location button at a location that is a percentage of the user's screen size.
                let screenSize = geometry.frame(in: .global)
                let screenWidth = screenSize.width
                let screenHeight = screenSize.height
                
                LocationButton(.currentLocation) {
                    viewModel.locationManager.requestWhenInUseAuthorization()
                    viewModel.isUpdatingLocation = true
                    viewModel.locationManager.startUpdatingLocation()
                    
                    // Set a timeout for the location update process
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        // Check if location is still being updated
                        if viewModel.isUpdatingLocation {
                            // If location update is still in progress after 10 seconds, show an alert
                            let alert = UIAlertController(title: "Location could not be determined. Please check if location permissions have been granted.", message: nil, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootViewController = windowScene.windows.first?.rootViewController {
                                rootViewController.topMostViewController().present(alert, animated: true, completion: nil)
                            }
                            
                            // Stop location update process
                            viewModel.locationManager.stopUpdatingLocation()
                            viewModel.isUpdatingLocation = false
                        }
                    }
                }
                .tint(.orange)
                .foregroundColor(.white)
                .cornerRadius(20, antialiased: true)
                .labelStyle(.iconOnly)
                .symbolVariant(.fill)
                .position(x: screenWidth - 45, y: screenHeight * 0.66)
                .overlay(
                    // Progress indicator overlay while the app is checking for the user's location
                    Group {
                        if viewModel.isUpdatingLocation {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 20, height: 20)
                        }
                    }
                        .animation(.easeInOut, value: viewModel.isUpdatingLocation)
                        .position(x: screenWidth - 45, y: screenHeight * 0.66)
                )
            }
            
            // **** Bottom Sheet ****            
            // Set the bottom sheet as an overlayed sheet in the ZStack.
            .bottomSheet(
                presentationDetents: [.fraction(0.3),.medium, .large],
                isPresented: .constant(true), 
                sheetCornerRadius: 20 
            ) 
            {
                // **** Bottom Sheet Scroll View ****
                // Set the bottom sheet content in a VStack.                    
                BusinessesListView(elements: visibleElements)
                    .environmentObject(viewModel)
                
                // Show the About sheet even when the bottom sheet is showing (Swift doesn't normally allow more than one sheet showing at the same time).
                    .sheet(isPresented: $showingAbout) {
                        AboutView()
                    }
            } onDismiss: {
            }
        }
        // Prevents location button from moving with keyboard. Need to make sure this doesn't mess anything up when searching is introduced.
        .ignoresSafeArea(.keyboard)
        
        // On View Appear Actions
        .onAppear {
            // Get elements
            apiManager.getElements { elements in
                DispatchQueue.main.async {
                    self.elements = elements
                }
            }
            // Determine elements visible in user view
            cancellable = viewModel.visibleElementsSubject.sink(receiveValue: { updatedVisibleElements in
                visibleElements = updatedVisibleElements
            })
            // Update user location
            cancellableUserLocation = viewModel.userLocationSubject.sink(receiveValue: { updatedUserLocation in
                userLocation = updatedUserLocation
            })
            // When user stops moving map
            mapStoppedMovingCancellable = viewModel.mapStoppedMovingSubject.sink(receiveValue: {
                // Any additional logic that should be executed when the map stops moving can be added here.
            })
        }
    }    
    
    func mapView(elements: [Element]) -> some View {
        MapView(elements: $elements)
            .environmentObject(viewModel)
    }
    
    struct MapView: UIViewRepresentable {
        @Binding var elements: [Element]?
        @EnvironmentObject var viewModel: ContentViewModel
        
        func makeCoordinator() -> ContentViewModel {
            viewModel
        }
        
        func makeUIView(context: Context) -> MKMapView {
            let mapView = MKMapView()
            mapView.delegate = context.coordinator
            setupCluster(mapView: mapView)
            mapView.showsUserLocation = true
            return mapView
        }
        
        // Update annotations on map
        func updateUIView(_ mapView: MKMapView, context: Context) {
            if mapView.region != viewModel.region {
                // Makes sure region is set on map.
                mapView.setRegion(viewModel.region, animated: true) 
                
                // Only show annotations within 25 miles of center of current map view
                if let elements = elements {
                    let newAnnotations = elements.compactMap { element -> Annotation? in
                        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else { return nil }
                        let location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        let distance = viewModel.distanceFromCenter(location: location)
                        if distance <= (25 * 1609.344) { // miles to meters
                            let annotation = Annotation(element: element)
                            return annotation
                        }
                        return nil
                    }
                    
                    // Remove old annotations
                    let oldAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
                    mapView.removeAnnotations(oldAnnotations)
                    
                    // Add new annotations
                    mapView.addAnnotations(newAnnotations)
                }
            }
        }
        
        // Setup Cluster
        private func setupCluster(mapView: MKMapView) {
            let clusteringIdentifier = "Cluster"
            mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: clusteringIdentifier)
        }
    }
}

// ContentViewModel
final class ContentViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate {
    // Sets the initial state of the map before getting user location. Coordinates are for Nashville, TN.
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.13, longitude: -86.775), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    @Published var userLocation: CLLocation?
    @Published var isUpdatingLocation = false
    
    let locationManager = CLLocationManager()
    let userLocationSubject = PassthroughSubject<CLLocation?, Never>()
    let visibleElementsSubject = PassthroughSubject<[Element], Never>()
    let mapStoppedMovingSubject = PassthroughSubject<Void, Never>()
    
    private var debounceTimer: Cancellable?
    weak var mapView: MKMapView?
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    // Request location
    func requestWhenInUseLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // Get latest location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else {
            // TODO: Show an error
            return
        }
        // Update map view to show user location
        DispatchQueue.main.async {
            self.updateMapRegion(center: latestLocation.coordinate)
            self.userLocation = latestLocation
            self.userLocationSubject.send(latestLocation)
        }
        manager.stopUpdatingLocation() // Stop updating location once we have the user's location
        userLocation = locations.last // Set the user's location in the view model
        isUpdatingLocation = false    // Set isUpdatingLocation to false so the progress view disappears
    }

    // locationManager failure scenario (could not get user location)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO: Need better error handling
        print(error.localizedDescription)
    }
    
    // Calculate distance between element and user location
    func distanceInMiles(element: Element) -> Double? {
        guard let userLocation = userLocation,
              let lat = element.osmJSON?.lat,
              let lon = element.osmJSON?.lon else {
            return nil
        }
        let location = CLLocation(latitude: lat, longitude: lon)
        let distanceInMeters = userLocation.distance(from: location)
        let distanceInMiles = distanceInMeters / 1609.34
        return distanceInMiles
    }
    
    // mapView Function
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let reuseIdentifier = "AnnotationView"
        var view: MKMarkerAnnotationView?
        
        if let cluster = annotation as? MKClusterAnnotation {
            view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
            view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
            view?.markerTintColor = .orange
            view?.glyphText = String(cluster.memberAnnotations.count)
        } else if let annotation = annotation as? Annotation {
            if annotation.element == nil {
                fatalError("Failed to get element from annotation.")
            }
            view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
            view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
            view?.canShowCallout = true
            view?.markerTintColor = .orange
            view?.glyphText = nil
            view?.glyphTintColor = .white
            view?.glyphImage = UIImage(systemName: "location.circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            view?.displayPriority = .required
        }
        return view
    }
    
    // Determining distance from center
    func distanceFromCenter(location: CLLocationCoordinate2D) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let annotationLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        return centerLocation.distance(from: annotationLocation)
    }
    
    // Update map region
    func updateMapRegion(center: CLLocationCoordinate2D) {
        self.region = MKCoordinateRegion(center: center, span: region.span)
    }
    
    // Detecting when map view visible region changes
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        debounceTimer?.cancel()
        debounceTimer = Just(())
            .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateMapRegion(center: mapView.region.center)
                let visibleAnnotations = mapView.annotations(in: mapView.visibleMapRect)
                let visibleElements = visibleAnnotations.compactMap { ($0 as? Annotation)?.element }
                self.visibleElementsSubject.send(visibleElements)
                self.mapStoppedMovingSubject.send(())
            }
    }
}

// Annotation Class
class Annotation: NSObject, Identifiable, MKAnnotation {
    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id
    }
    
    let id = UUID()
    let element: Element?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: element?.osmJSON?.lat ?? 0, longitude: element?.osmJSON?.lon ?? 0)
    }
    
    var title: String? {
        element?.osmJSON?.tags?["name"]
    }
    
    init(element: Element) {
        self.element = element
    }
}

// AnnotationView Class
class AnnotationView: MKMarkerAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        updateView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var annotation: MKAnnotation? {
        willSet {
            updateView()
        }
    }
    
    // UpdateView Function
    private func updateView() {
        guard let annotation = annotation else { return }
        if let _ = annotation as? Annotation {
            clusteringIdentifier = "element"
        } else if let cluster = annotation as? MKClusterAnnotation {
            clusteringIdentifier = nil
            displayPriority = .defaultHigh
            let totalCount = cluster.memberAnnotations.count
            markerTintColor = totalCount < 5 ? .orange : totalCount < 10 ? .yellow : .red
            glyphText = "\(totalCount)"
        }
        canShowCallout = true
    }
}
