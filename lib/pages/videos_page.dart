import 'dart:convert';
import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectfm/app/modules/root/app_controller.dart';
import 'package:connectfm/models/video_model.dart';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:waveui/waveui.dart';
import 'package:google_fonts/google_fonts.dart';


class VideoListScreen extends StatefulWidget {
  const VideoListScreen({Key? key});

  @override
  _VideoListScreenState createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  final String apiKey = "AIzaSyCgI_dJaGjiXB6EoO56Sk0ZfyafneZwpPg";
  final String channelId = "UChVmpG7svTIbwlA1Ie4BfKA";
  int maxResults = 30;
  bool isLoading = false;
  List<YoutubeModel> videos = [];
  bool isError = false;
  final AppController controller = Get.find();
  late String nextPageToken;
  var unescape = HtmlUnescape();
  late ScrollController _scrollController;



  int convertDurationToSeconds(String duration) {
    RegExp regExp = RegExp(r'(\d+)');
    Iterable<Match> matches = regExp.allMatches(duration);

    int seconds = 0;
    int multiplier = 1;

    List<String> matchList = matches.map((m) => m.group(0)!).toList();
    matchList = matchList.reversed.toList();

    for (String match in matchList) {
      seconds += int.parse(match) * multiplier;
      multiplier *= 60;
    }

    return seconds;
  }

  Future<void> _loadVideos() async {
    setState(() {
      isLoading = true;
    });

    String updatedToken = await _loadVideosByDuration("any", nextPageToken);
    nextPageToken = updatedToken;

    setState(() {
      isError = false;
      isLoading = false;
    });

    print("Fetched ${videos.length} videos. nextPageToken: $nextPageToken");
  }

  Future<String> _loadVideosByDuration(String videoDuration, String nextPageToken) async {
    setState(() {
      isLoading = true;
    });

    String apiUrl = "https://www.googleapis.com/youtube/v3/search";
    DateTime oneWeekAgo = DateTime.now().subtract(Duration(days: 90));
    String publishedAfter = oneWeekAgo.toUtc().toIso8601String();
    String params =
        "?part=snippet&channelId=$channelId&type=video&videoType=$videoDuration&order=date&maxResults=$maxResults&pageToken=$nextPageToken&key=$apiKey&publishedAfter=$publishedAfter";

    Uri url = Uri.parse(apiUrl + params);

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);

        if (data.containsKey('items')) {
          List<YoutubeModel> newVideos = [];
          for (var item in data['items']) {
            YoutubeModel video = YoutubeModel.fromJson(item);

            // Fetch video duration separately
            int durationInSeconds = await _getVideoDuration(video.id.videoId);

            // Check if the video duration is greater than 1 minute
            if (durationInSeconds > 60) {
              newVideos.add(video);
            }
          }

          String updatedNextPageToken = data.containsKey('nextPageToken') ? data['nextPageToken'] : '';

          // Append new videos to the existing list
          if (nextPageToken.isEmpty) {
            // If nextPageToken is empty, it means it's the initial load, so replace the existing videos.
            videos = newVideos;
          } else {
            // If nextPageToken is not empty, it's a subsequent load, so append the new videos.
            videos.addAll(newVideos);
          }

          setState(() {
            isError = false;
            isLoading = false;
            nextPageToken = updatedNextPageToken; // Update nextPageToken
          });

          print("Videos in API response: ${newVideos.length}");
          print("Total videos after combining: ${videos.length}");
          print("Updated nextPageToken: $updatedNextPageToken");

          return updatedNextPageToken;
        }
      } else {
        log(response.statusCode.toString() + response.body);
        setState(() {
          isError = true;
          isLoading = false;
        });
      }
    } catch (error) {
      print("Error: $error");
      setState(() {
        isError = true;
        isLoading = false;
      });
    }

    return nextPageToken;
  }

  Future<int> _getVideoDuration(String videoId) async {
    String apiUrl = "https://www.googleapis.com/youtube/v3/videos";
    String params = "?part=contentDetails&id=$videoId&key=$apiKey";

    Uri url = Uri.parse(apiUrl + params);

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);

        if (data.containsKey('items') && data['items'].isNotEmpty) {
          String duration = data['items'][0]['contentDetails']['duration'];
          return convertDurationToSeconds(duration);
        }
      } else {
        log(response.statusCode.toString() + response.body);
      }
    } catch (error) {
      print("Error: $error");
    }

    return 0;
  }

  Future<void> _loadMoreVideos() async {
    print("Loading more videos...");

    if (!isLoading && nextPageToken.isNotEmpty) {
      String updatedToken = await _loadVideosByDuration("any", nextPageToken);
      if (updatedToken.isNotEmpty) {
        setState(() {
          nextPageToken = updatedToken;
        });
      }
    }
  }



  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent &&
        !_scrollController.position.outOfRange) {
      print("Reached the end, calling _loadMoreVideos()");
      _loadMoreVideos();
    }
  }






  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    videos = [];
    nextPageToken = '';
    _loadVideos();
  }



  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.sizeOf(context).width;
    print("Building UI - itemCount: ${videos.length}");
    return Scaffold(
      backgroundColor: Get.theme.cardColor,
      appBar: WaveAppBar(
        onBackPressed: () => controller.currentNavIndex.value = 0,
        title: Text('Latest Videos'),
      ),
      body: isError
          ? const Column(
        children: [Text("Please try again later, failed to load videos")],
      )
          : ListView.separated(
        controller: _scrollController,
        separatorBuilder: (context, index) => Container(),
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: videos.length + (isLoading ? 1 : 0), // Add 1 for the loader
        itemBuilder: (context, index) {
          print("AR ${videos.length}");
          if (index < videos.length) {
            Snippet item = videos[index].snippet;
            return InkWell(
              onTap: () => _launchYouTubeVideo(videos[index].id.videoId),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 10),
                child: Column(
                  children: [
                    SizedBox(
                      height: 8,
                    ),
                    Row(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CachedNetworkImage(
                                fit: BoxFit.cover,
                                height: width * 0.3,
                                width: width * 0.45,
                                imageUrl: item.thumbnails.high.url),
                            const Icon(
                              Icons.play_circle_fill_outlined,
                              color: Colors.white,
                              size: 35,
                            )
                          ],
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(unescape.convert(item.title),
                                  maxLines: 3,
                                  style: GoogleFonts.roboto(
                                      fontSize: 17, fontWeight: FontWeight.w500)),
                              const SizedBox(
                                height: 10,
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    FluentIcons.calendar_12_regular,
                                    size: 14,
                                  ),
                                  const SizedBox(
                                    width: 4,
                                  ),
                                  Text(
                                    DateFormat.yMMMMd()
                                        .format(DateTime.parse(item.publishTime)),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black45),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                    SizedBox(
                      height: 10,
                    ),
                    Divider(),
                  ],
                ),
              ),
            );
          } else {
            return Center(child: LinearProgressIndicator());
          }
        },
      ),
    );
  }
}

void _launchYouTubeVideo(String videoId) async {
  Uri url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
  await launchUrl(url);
}





