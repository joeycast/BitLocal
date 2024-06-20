// ContentView.swift

import UIKit
import SwiftUI
import MapKit
import CoreLocationUI
import Combine

@available(iOS 16.4, *)
struct ContentView: View {
    
    @StateObject private var viewModel = ContentViewModel()
    
    @State public var showingAbout = false
    @State public var elements: [Element]?
    @State public var visibleElements: [Element] = []
    
    @State private var userLocation: CLLocation?
    @State private var cancellable: Cancellable?
    @State private var mapStoppedMovingCancellable: Cancellable?
    @State private var cancellableUserLocation: Cancellable?
    @State private var firstLocationUpdate: Bool = true
    
    let appName = "BitLocal"   
    let apiManager = APIManager()
    
    var body: some View {
        
        // **** Main View ****
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            
            if screenWidth > 768 || geometry.size.height > 1024 { // iPad layout
                NavigationView {
                    BusinessesListView(elements: visibleElements)
                        .environmentObject(viewModel)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                CustomiPadNavigationStackTitleView()
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                InfoButtonView(showingAbout: $showingAbout)
                            }
                        }
                    ZStack {
                        if let elements = elements {
                            mapView(elements: elements)
                                .ignoresSafeArea()
                                .onAppear {
                                    viewModel.locationManager.requestWhenInUseAuthorization()
                                    viewModel.locationManager.startUpdatingLocation()
                                }
                        }
                        locationButtonView(isIPad: true)
                    }
                }
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
            } else { // iPhone layout
                ZStack {
                    if let elements = elements {
                        mapView(elements: elements)
                            .ignoresSafeArea()
                            .onAppear {
                                viewModel.locationManager.requestWhenInUseAuthorization()
                                viewModel.locationManager.startUpdatingLocation()
                            }
                    }
                    ZStack {
                        VStack {
                            iPhoneHeaderView(screenWidth: screenWidth)
                            Spacer()
                            locationButtonView(isIPad: false)
                        }   
                    }
                    
                    // **** Bottom Sheet ****
                    .bottomSheet(
                        presentationDetents: [.fraction(0.3), .medium, .large],
                        isPresented: .constant(true),
                        sheetCornerRadius: 20
                    ) {
                        // **** Bottom Sheet Scroll View ****
                        BusinessesListView(elements: visibleElements)
                            .environmentObject(viewModel)
                        
                        // Show the About sheet even when the bottom sheet is showing (Swift doesn't normally allow more than one sheet showing at the same time).
                            .sheet(isPresented: $showingAbout) {
                                AboutView()
                            }
                    } onDismiss: {}
                }
                .ignoresSafeArea(.keyboard)
            }
        }
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
                
                // Zoom in on user's location on the first launch and subsequent app launches
                if firstLocationUpdate {
                    if let coordinate = userLocation?.coordinate {
                        let newZoomLevel = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5) // set the desired zoom level
                        viewModel.updateMapRegion(center: coordinate, span: newZoomLevel)
                    }
                    firstLocationUpdate = false
                }
            })
            // When user stops moving map
            mapStoppedMovingCancellable = viewModel.mapStoppedMovingSubject.sink(receiveValue: {
                // Any additional logic that should be executed when the map stops moving can be added here.
            })
        }
    }
    
    // iPhone Header
    func iPhoneHeaderView(screenWidth: CGFloat) -> some View {
        ZStack {
            GeometryReader { geometry in
                let screenSize = geometry.frame(in: .global)
                let screenWidth = screenSize.width
                let roundedRectangleRadius = 10
                
                Rectangle()
                    .cornerRadius(CGFloat(roundedRectangleRadius))
                    .foregroundColor(Color(UIColor.systemBackground)) // Sets the color based on light/dark mode.
                    .frame(width: screenWidth, height: CGFloat(115 + roundedRectangleRadius)) 
                    .padding(.top, -CGFloat(roundedRectangleRadius))
                    .ignoresSafeArea()
            }
            
            VStack(alignment: .leading) {
                
                // BitLocal text
                HStack {
                    Spacer()
                    HStack(spacing: 0) {
                        Text(" bit")
                            .font(.custom("Ubuntu-LightItalic", size: 28))
                            .foregroundColor(.orange)
                        
                        Text("local ")
                            .font(.custom("Ubuntu-MediumItalic", size: 28))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    
                    // Info Button
                    InfoButtonView(showingAbout: $showingAbout)
                        .frame(maxWidth: 1, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 3)
                }
                .padding(.horizontal)
                .frame(width: screenWidth, height: 1)
                Spacer()
            }
            .padding(.top, 30)
        }
    }
    
    // Navigation Stack Title View for iPad
    struct CustomiPadNavigationStackTitleView: View {
        var body: some View {
            HStack(spacing: 0) {
                Text(" bit")
                    .font(.custom("Ubuntu-LightItalic", size: 28))
                    .foregroundColor(.orange)
                
                Text("local ")
                    .font(.custom("Ubuntu-MediumItalic", size: 28))
                    .foregroundColor(.orange)
                
            }
            .padding(.trailing)
        }
    }
    
    // Info Button View
    struct InfoButtonView: View {
        @Binding var showingAbout: Bool
        
        var body: some View {
            Button(action: {
                showingAbout.toggle()
            }) {
                Image(systemName: "info.circle")
                    .padding()
                    .foregroundColor(.orange)
                    .contentShape(Circle())
                    .clipShape(Circle())
            }
        }
    }
    
    // Location Button View
    func locationButtonView(isIPad: Bool) -> some View {
        GeometryReader { geometry in
            let screenSize = geometry.frame(in: .global)
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            
            let buttonXPosition: CGFloat = screenWidth > 768 ? screenWidth - 60 : screenWidth - 45
            let buttonYPosition: CGFloat = screenWidth > 768 ? screenHeight * 0.95 : screenHeight * 0.30
            
            LocationButton(.currentLocation) {
                viewModel.locationManager.requestWhenInUseAuthorization()
                viewModel.isUpdatingLocation = true
                viewModel.locationManager.startUpdatingLocation()
                
                // Zoom in on user's location after tapping the location button
                if let coordinate = userLocation?.coordinate {
                    let newZoomLevel = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5) // set the desired zoom level
                    viewModel.updateMapRegion(center: coordinate, span: newZoomLevel)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if viewModel.isUpdatingLocation {
                        let alert = UIAlertController(title: "Location could not be determined. Please check if location permissions have been granted.", message: nil, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            rootViewController.topMostViewController().present(alert, animated: true, completion: nil)
                        }
                        
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
            .position(x: buttonXPosition, y: buttonYPosition)
            .overlay(
                Group {
                    if viewModel.isUpdatingLocation {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                }
                    .animation(.easeInOut, value: viewModel.isUpdatingLocation)
                    .position(x: buttonXPosition, y: buttonYPosition + 3)
            )
            GeometryReader { attributionGeometry in
                let attributionXPosition = isIPad ? 85 : 85
                let attributionYPosition = isIPad ? screenHeight * 0.95 : screenHeight * 0.37
                OpenStreetMapAttributionView()
                    .position(x: attributionGeometry.size.width * CGFloat(attributionXPosition) / screenWidth, y: attributionGeometry.size.height * CGFloat(attributionYPosition) / screenHeight)
            }
        }
    }
    
    struct OpenStreetMapAttributionView: View {
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.colorScheme) var colorScheme
        @State private var isFaded = false
        
        var body: some View {
            Button(action: {
                if let url = URL(string: "https://www.openstreetmap.org/copyright") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Map data from ")
                    .font(.system(size: 10))
                    .foregroundColor(colorScheme == .light ? Color.black : Color.white)
                +
                Text("OpenStreetMap")
                    .font(.system(size: 10))
                    .underline()
                    .foregroundColor(colorScheme == .light ? Color.black : Color.white)
            }
            .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
            .background(Color(colorScheme == .light ? UIColor.white : UIColor.black).opacity(colorScheme == .light ? 0.6 : 0.4))
            .cornerRadius(3)
            .opacity(isFaded ? 0 : 1)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    withAnimation(.easeInOut(duration: 3)) {
                        isFaded = true
                    }
                }
            }
            .onChange(of: scenePhase) { newScenePhase in
                if newScenePhase == .active {
                    withAnimation(.easeInOut(duration: 0)) {
                        isFaded = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        withAnimation(.easeInOut(duration: 3)) {
                            isFaded = true
                        }
                    }
                }
            }
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
        
        // Update the region change in this method
        func updateUIView(_ mapView: MKMapView, context: Context) {
            let targetRegion = viewModel.region
            
            // Check if the regional changes are needed
            if mapView.region != targetRegion {
                let fittedRegion = mapView.regionThatFits(targetRegion)
                mapView.setRegion(fittedRegion, animated: true)
            }
            
            // Call the updateAnnotations function to refresh annotations when the region is updated
            updateAnnotations(mapView: mapView, elements: elements)
        }
        
        func updateAnnotations(mapView: MKMapView, elements: [Element]?) {
            if let elements = elements {
                let newAnnotations = elements.compactMap { element -> Annotation? in
                    guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else { return nil }
                    let location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let distance = viewModel.distanceFromCenter(location: location)
                    if distance <= CLLocationDistance(25 * 1609.344) { // Miles to meters
                        if (element.deletedAt == nil || element.deletedAt == "") && (element.osmJSON?.tags?.name != nil || element.osmJSON?.tags?.operator != nil) {
                            // Only show element as annotation if it has not been deleted and has a name or operator
                            let annotation = Annotation(element: element)
                            return annotation
                        }
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
    @Published var geocodingCache = LRUCache<String, Address>(maxSize: 100)
    
    let locationManager = CLLocationManager()
    let userLocationSubject = PassthroughSubject<CLLocation?, Never>()
    let visibleElementsSubject = PassthroughSubject<[Element], Never>()
    let mapStoppedMovingSubject = PassthroughSubject<Void, Never>()
    let geocoder = Geocoder(maxConcurrentRequests: 5)
    
    private var debounceTimer: Cancellable?
    weak var mapView: MKMapView?
    
    override init() {
        super.init()
        locationManager.delegate = self
        mapView?.delegate = self
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
    func updateMapRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil) {
        let updatedSpan = span ?? region.span
        self.region = MKCoordinateRegion(center: center, span: updatedSpan)
    }
    
    // Detecting when map view visible region changes
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        self.updateMapRegion(center: mapView.region.center, span: mapView.region.span)
        
        // Update visible elements with a slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateAnnotations(for: mapView)
        }
    }
    
    func updateAnnotations(for mapView: MKMapView) {
        let visibleAnnotations = mapView.annotations(in: mapView.visibleMapRect)
        let visibleElements = visibleAnnotations.compactMap { ($0 as? Annotation)?.element }
        
        self.visibleElementsSubject.send(visibleElements)
        self.mapStoppedMovingSubject.send(())
    }
    
    func updateVisibleElements(for annotations: [MKAnnotation]) {
        let visibleElements = annotations.compactMap { ($0 as? Annotation)?.element }
        self.visibleElementsSubject.send(visibleElements)
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
        element?.osmJSON?.tags?.name
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
