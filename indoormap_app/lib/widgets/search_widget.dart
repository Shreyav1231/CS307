import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:latlong2/latlong.dart';
import '../data/map_data_provider.dart';

class SearchWidget extends StatelessWidget {
  final List<MapNode> nodes;
  final Function(MapNode) onNodeSelected;

  const SearchWidget({
    Key? key,
    required this.nodes,
    required this.onNodeSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TypeAheadField<MapNode>(
        builder: (context, controller, focusNode) {
          return Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(30),
            child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'Search for rooms...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                ),
            ),
          );
        },
        suggestionsCallback: (pattern) {
          if (pattern.isEmpty) return [];
          return nodes.where((node) {
            final nameLower = node.name.toLowerCase();
            final idLower = node.id.toLowerCase();
            final queryLower = pattern.toLowerCase();
            return nameLower.contains(queryLower) || idLower.contains(queryLower);
          }).toList();
        },
        itemBuilder: (context, suggestion) {
          return ListTile(
            leading: const Icon(Icons.place),
            title: Text(suggestion.name),
            subtitle: Text(suggestion.type.toUpperCase()),
          );
        },
        onSelected: (suggestion) {
          onNodeSelected(suggestion);
        },
      ),
    );
  }
}
