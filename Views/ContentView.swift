import SwiftUI
import MapKit
import CoreLocationUI

struct ContentView: View {
    
    @StateObject private var viewModel = ContentViewModel()
    @State public var showingAbout = false
    @State public var userSearchText = ""
    @State public var elements: [Element]?
    
    let appName = "BitLocal"   
    let apiManager = APIManager()
    
    var body: some View {
        
        // **** Main ZStack ****
        ZStack() {    
            // **** Map ****
            // Sets the map as the background in the ZStack.
            if let elements = elements {
                Map(coordinateRegion: $viewModel.region,
                    showsUserLocation: true,
                    annotationItems: elements) { element -> MapMarker in
                    guard let osmJSON = element.osmJSON, let latitude = osmJSON.lat, let longitude = osmJSON.lon else {
                        return MapMarker(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), tint: .orange) // replace with default location or no marker
                    }
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    return MapMarker(coordinate: coordinate, tint: .orange)
                }
                    .tint(.orange)
                    .ignoresSafeArea()
                    .clusteredAnnotation(spread: .perCluster(.absolute(40)), radius: .absolute(40))
            }



            // **** Background Header Rectangle ****
            GeometryReader { geometry in 
                let screenSize = geometry.frame(in: .global)
                let screenWidth = screenSize.width
                let roundedRectangleRadius = 10
                
                Rectangle()
                    .cornerRadius(CGFloat(roundedRectangleRadius))
                    .foregroundColor(Color(UIColor.systemBackground)) // Sets the color based on light/dark mode.
                    .frame(width: screenWidth, height: CGFloat(115 + roundedRectangleRadius))
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
            
            // **** Search Bar ****
            // Uses GeometryReader to dynamically set search bar position based on device screen size.
            GeometryReader { geometry in
                // Use the geometry to determine the size of the screen
                let screenSize = geometry.frame(in: .global)
                let screenWidth = screenSize.width
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .padding(.leading)
                    TextField("Search", text: $userSearchText)
                        .frame(maxWidth: 450, minHeight: 35)
                }
                .background(Color(UIColor.systemBackground)) // Sets the color based on light/dark mode.
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.33), lineWidth: 1)
                )
                .padding(.top)
                .padding(.horizontal)
                .position(x: screenWidth * 0.5, y: 57)
            }
            
            // **** Location Button ****            
            // Get current location button. Run requestAllowOnceLocationPermission on tap.
            // TODO: How to make iPad cursor snap to button?
            GeometryReader { geometry in
                // Use the geometry to determine the size of the screen so I can set the location button at a location that is a percentage of the user's screen size.
                let screenSize = geometry.frame(in: .global)
                let screenWidth = screenSize.width
                let screenHeight = screenSize.height
                
                LocationButton(.currentLocation) {
                    viewModel.requestAllowOnceLocationPermission()
                }
                .tint(.orange)
                .foregroundColor(.white)
                .cornerRadius(20, antialiased: true)
                .labelStyle(.iconOnly)
                .symbolVariant(.fill)
                .position(x: screenWidth - 45, y: screenHeight * 0.66)
                
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
                BusinessesListView()
                
                // Show the About sheet even when the bottom sheet is showing (Swift doesn't normally allow more than one sheet showing at the same time).
                    .sheet(isPresented: $showingAbout) {
                        AboutView()
                    }
            } onDismiss: {
            }
        }
        // Prevents location button from moving with keyboard. Need to make sure this doesn't mess anything up when searching is introduced.
        .ignoresSafeArea(.keyboard)
        .onAppear {
            apiManager.getElements { elements in
                DispatchQueue.main.async {
                    self.elements = elements
                }
            }
        }
    }    
}

// Getting user's location
final class ContentViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    // Sets the initial state of the map before getting user location. Coordinates are for Nashville, TN.
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.13, longitude: -86.775), span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
    
    let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    // Request location
    func requestAllowOnceLocationPermission() {
        locationManager.requestLocation()
    }
    // Get latest location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else {
            // TODO: Show an error
            return
        }
        // Update map view to show user location
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(center: latestLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO: Need better error handling
        print(error.localizedDescription)
    }
    
}
