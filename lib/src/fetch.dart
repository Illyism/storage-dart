import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:mime/mime.dart';
import 'package:storage_client/src/types.dart';
import 'package:universal_io/io.dart';

Fetch fetch = Fetch();

class StorageError {
  final String message;
  final String? error;
  final String? statusCode;

  StorageError(this.message, {this.error, this.statusCode});

  StorageError.fromJson(dynamic json)
      : assert(json is Map<String, dynamic>),
        message = json['message'] as String,
        error = json['error'] as String?,
        statusCode = json['statusCode'] as String?;

  @override
  String toString() => message;
}

class StorageResponse<T> {
  final StorageError? error;
  final T? data;

  StorageResponse({this.data, this.error});

  bool get hasError => error != null;
}

class Fetch {
  bool _isSuccessStatusCode(int code) {
    return code >= 200 && code <= 299;
  }

  MediaType? _parseMediaType(String path) {
    try {
      final mime = lookupMimeType(path);
      return MediaType.parse(mime ?? '');
    } catch (error) {
      rethrow;
    }
  }

  StorageError _handleError(dynamic error) {
    if (error is http.Response) {
      try {
        final data = json.decode(error.body) as Map<String, dynamic>;
        return StorageError.fromJson(data);
      } on FormatException catch (_) {
        return StorageError(error.body);
      }
    } else {
      return StorageError(error.toString());
    }
  }

  Future<StorageResponse> _handleRequest(
    String method,
    String url,
    dynamic body,
    FetchOptions? options,
  ) async {
    try {
      final headers = options?.headers ?? {};
      if (method != 'GET') {
        headers['Content-Type'] = 'application/json';
      }
      final bodyStr = json.encode(body ?? {});
      final request = http.Request(method, Uri.parse(url))
        ..headers.addAll(headers)
        ..body = bodyStr;

      final streamedResponse = await request.send();
      return _handleResponse(streamedResponse, options);
    } catch (e) {
      return StorageResponse(error: _handleError(e));
    }
  }

  Future<StorageResponse> _handleMultipartRequest(
    String method,
    String url,
    File file,
    FileOptions fileOptions,
    FetchOptions? options,
  ) async {
    try {
      final headers = options?.headers ?? {};
      final multipartFile = http.MultipartFile.fromBytes(
        '',
        file.readAsBytesSync(),
        filename: file.path,
        contentType: _parseMediaType(file.path),
      );
      final request = http.MultipartRequest(method, Uri.parse(url))
        ..headers.addAll(headers)
        ..files.add(multipartFile)
        ..fields['cacheControl'] = fileOptions.cacheControl
        ..headers['x-upsert'] = fileOptions.upsert.toString();

      final streamedResponse = await request.send();
      return _handleResponse(streamedResponse, options);
    } catch (e) {
      return StorageResponse(error: _handleError(e));
    }
  }

  Future<StorageResponse> _handleBinaryFileRequest(
    String method,
    String url,
    Uint8List data,
    FileOptions fileOptions,
    FetchOptions? options,
  ) async {
    try {
      final headers = options?.headers ?? {};
      final multipartFile = http.MultipartFile.fromBytes(
        '',
        data,
        // request fails with null filename so set it empty instead.
        filename: '',
        contentType: _parseMediaType(url),
      );
      final request = http.MultipartRequest(method, Uri.parse(url))
        ..headers.addAll(headers)
        ..files.add(multipartFile)
        ..fields['cacheControl'] = fileOptions.cacheControl
        ..headers['x-upsert'] = fileOptions.upsert.toString();

      final streamedResponse = await request.send();
      return _handleResponse(streamedResponse, options);
    } catch (e) {
      return StorageResponse(error: _handleError(e));
    }
  }

  Future<StorageResponse> _handleResponse(
    http.StreamedResponse streamedResponse,
    FetchOptions? options,
  ) async {
    try {
      final response = await http.Response.fromStream(streamedResponse);

      if (_isSuccessStatusCode(response.statusCode)) {
        if (options?.noResolveJson == true) {
          return StorageResponse(data: response.bodyBytes);
        } else {
          final jsonBody = json.decode(response.body);
          return StorageResponse(data: jsonBody);
        }
      } else {
        throw response;
      }
    } catch (e) {
      return StorageResponse(error: _handleError(e));
    }
  }

  Future<StorageResponse> get(String url, {FetchOptions? options}) async {
    return _handleRequest('GET', url, {}, options);
  }

  Future<StorageResponse> post(String url, dynamic body,
      {FetchOptions? options}) async {
    return _handleRequest('POST', url, body, options);
  }

  Future<StorageResponse> put(String url, dynamic body,
      {FetchOptions? options}) async {
    return _handleRequest('PUT', url, body, options);
  }

  Future<StorageResponse> delete(String url, dynamic body,
      {FetchOptions? options}) async {
    return _handleRequest('DELETE', url, body, options);
  }

  Future<StorageResponse> postFile(
      String url, File file, FileOptions fileOptions,
      {FetchOptions? options}) async {
    return _handleMultipartRequest('POST', url, file, fileOptions, options);
  }

  Future<StorageResponse> putFile(
      String url, File file, FileOptions fileOptions,
      {FetchOptions? options}) async {
    return _handleMultipartRequest('PUT', url, file, fileOptions, options);
  }

  Future<StorageResponse> postBinaryFile(
      String url, Uint8List data, FileOptions fileOptions,
      {FetchOptions? options}) async {
    return _handleBinaryFileRequest('POST', url, data, fileOptions, options);
  }

  Future<StorageResponse> putBinaryFile(
      String url, Uint8List data, FileOptions fileOptions,
      {FetchOptions? options}) async {
    return _handleBinaryFileRequest('PUT', url, data, fileOptions, options);
  }
}
